"""Scoped chat lifecycle, context selection, and LLM coordination."""

import json
from datetime import UTC, datetime
from uuid import UUID

from app.core.errors import ApplicationError
from app.integrations.llm.provider import (
    LLMRequest,
    LLMTask,
    LLMTool,
    ReminderProposalDraft,
)
from app.integrations.llm.router import LLMRouter
from app.integrations.memory.provider import MemoryProvider
from app.modules.chats.models import ChatMessage, ChatSession
from app.modules.chats.repository import ChatRepository
from app.modules.chats.schemas import (
    ChatCreate,
    ChatDetailResponse,
    ChatMessageCreate,
    ChatMessageResponse,
    ChatResponse,
    ChatUpdate,
    SendMessageResponse,
)
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.reminders.models import ReminderProposal
from app.modules.reminders.repository import ReminderRepository
from app.modules.reminders.schemas import ProposalResponse
from app.modules.users.schemas import SupportedLanguage
from app.modules.weather.tool import PlotForecastTool


class ChatService:
    """Keep persisted sessions isolated and send only bounded relevant context."""

    def __init__(
        self,
        *,
        repository: ChatRepository,
        farms: FarmRepository,
        diagnoses: DiagnosisRepository,
        memory: MemoryProvider,
        llm: LLMRouter,
        plot_forecast: PlotForecastTool,
        reminders: ReminderRepository,
    ) -> None:
        self._repository = repository
        self._farms = farms
        self._diagnoses = diagnoses
        self._memory = memory
        self._llm = llm
        self._plot_forecast = plot_forecast
        self._reminders = reminders

    async def create_chat(self, farmer_id: UUID, data: ChatCreate) -> ChatResponse:
        farm_id, plot_id, case_id = await self._validate_scope(farmer_id, data)
        chat = ChatSession(
            farmer_id=farmer_id,
            scope_type=data.scope_type.value,
            farm_id=farm_id,
            plot_id=plot_id,
            diagnosis_case_id=case_id,
            title="New conversation",
        )
        self._repository.add(chat)
        await self._repository.commit()
        await self._repository.refresh(chat)
        return ChatResponse.model_validate(chat)

    async def list_chats(
        self, farmer_id: UUID, *, include_archived: bool
    ) -> list[ChatResponse]:
        chats = await self._repository.list_chats(
            farmer_id, include_archived=include_archived
        )
        return [ChatResponse.model_validate(chat) for chat in chats]

    async def get_chat(self, farmer_id: UUID, chat_id: UUID) -> ChatDetailResponse:
        chat = await self._chat(farmer_id, chat_id)
        messages = await self._repository.recent_messages(farmer_id, chat_id, limit=100)
        return ChatDetailResponse(
            **ChatResponse.model_validate(chat).model_dump(),
            messages=[ChatMessageResponse.model_validate(item) for item in messages],
        )

    async def update_chat(
        self, farmer_id: UUID, chat_id: UUID, data: ChatUpdate
    ) -> ChatResponse:
        chat = await self._chat(farmer_id, chat_id)
        if "title" in data.model_fields_set:
            chat.title = data.title or chat.title
        if "archived" in data.model_fields_set:
            chat.archived_at = datetime.now(tz=UTC) if data.archived else None
        await self._repository.commit()
        await self._repository.refresh(chat)
        return ChatResponse.model_validate(chat)

    async def delete_chat(self, farmer_id: UUID, chat_id: UUID) -> None:
        await self._repository.delete(await self._chat(farmer_id, chat_id))
        await self._repository.commit()

    async def send_message(
        self,
        farmer_id: UUID,
        chat_id: UUID,
        data: ChatMessageCreate,
        *,
        preferred_language: SupportedLanguage | None,
    ) -> SendMessageResponse:
        chat = await self._chat(farmer_id, chat_id)
        if chat.archived_at is not None:
            raise ApplicationError(code="CHAT_ARCHIVED", status_code=409)
        recent = await self._repository.recent_messages(farmer_id, chat_id, limit=10)
        context = await self._context(farmer_id, chat, data.content)
        tools = self._tools(farmer_id, chat)
        task = LLMTask.AGRICULTURAL_GUIDANCE
        sequence = await self._repository.next_sequence(farmer_id, chat_id)
        user_message = ChatMessage(
            farmer_id=farmer_id,
            chat_id=chat_id,
            sequence=sequence,
            role="user",
            content=data.content,
        )
        self._repository.add(user_message)
        try:
            result = await self._llm.respond(
                LLMRequest(
                    task=task,
                    instructions=self._instructions(preferred_language),
                    input_text=self._input(recent, context, data.content),
                    farmer_id=farmer_id,
                    tools=tools,
                )
            )
            content = result.reply.short_answer
            if result.reply.details:
                content = f"{content}\n\n{result.reply.details}"
            if result.reply.treatment is not None:
                content = f"{content}\n\n{self._render_treatment(result.reply.treatment)}"
            assistant_message = ChatMessage(
                farmer_id=farmer_id,
                chat_id=chat_id,
                sequence=sequence + 1,
                role="assistant",
                content=content,
                model=result.model,
                provider_response_id=result.provider_response_id,
            )
            self._repository.add(assistant_message)
            reminder_proposal = self._pending_reminder(
                farmer_id, chat, result.reply.reminder_proposal
            )
            if reminder_proposal is not None:
                self._reminders.add(reminder_proposal)
            if chat.title == "New conversation":
                chat.title = self._local_title(data.content)
            await self._repository.commit()
        except Exception:
            await self._repository.rollback()
            raise
        await self._repository.refresh(user_message)
        await self._repository.refresh(assistant_message)
        if reminder_proposal is not None:
            await self._reminders.refresh(reminder_proposal)
        return SendMessageResponse(
            user_message=ChatMessageResponse.model_validate(user_message),
            assistant_message=ChatMessageResponse.model_validate(assistant_message),
            follow_up_questions=result.reply.follow_up_questions,
            reminder_proposal=(
                ProposalResponse.model_validate(reminder_proposal)
                if reminder_proposal is not None
                else None
            ),
        )

    @staticmethod
    def _pending_reminder(
        farmer_id: UUID,
        chat: ChatSession,
        draft: ReminderProposalDraft | None,
    ) -> ReminderProposal | None:
        if draft is None:
            return None
        return ReminderProposal(
            farmer_id=farmer_id,
            chat_id=chat.id,
            diagnosis_case_id=chat.diagnosis_case_id,
            plot_id=chat.plot_id,
            title=draft.title,
            due_at=draft.due_at,
            recurrence_days=draft.recurrence_days,
            status="pending",
        )

    def _tools(self, farmer_id: UUID, chat: ChatSession) -> tuple[LLMTool, ...]:
        """Expose only a forecast for the already-authorized plot in this chat."""

        if chat.plot_id is None:
            return ()
        plot_id = chat.plot_id

        async def get_plot_forecast() -> str:
            try:
                response = await self._plot_forecast.get(farmer_id, plot_id)
                return response.model_dump_json()
            except ApplicationError as exc:
                return json.dumps({"error": exc.code})

        return (
            LLMTool(
                name="get_plot_forecast",
                description=(
                    "Get the seven-day Open-Meteo forecast for the plot already linked "
                    "to this chat. Use it when weather can affect agricultural guidance."
                ),
                execute=get_plot_forecast,
            ),
        )

    async def _context(
        self, farmer_id: UUID, chat: ChatSession, query: str
    ) -> list[str]:
        context: list[str] = []
        if chat.farm_id is not None:
            farm = await self._farms.get_farm(farmer_id, chat.farm_id)
            if farm is None:
                raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
            context.append(f"Farm: {farm.name}")
        if chat.plot_id is not None:
            plot = await self._farms.get_plot(farmer_id, chat.plot_id)
            if plot is None:
                raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
            context.append(f"Plot: {plot.name}")
            crops = await self._farms.list_crops(farmer_id, plot.id)
            context.extend(
                f"Crop: {crop.name}; variety={crop.variety or 'unknown'}; stage={crop.stage}"
                for crop in crops
                if crop.cycle_ended_on is None
            )
            activities = await self._farms.list_activities(
                farmer_id, plot.id, limit=5
            )
            context.extend(
                f"Recent plot activity: {activity.title} at {activity.occurred_at.isoformat()}"
                for activity in activities
            )
            reminders = await self._reminders.list_plot_pending(
                farmer_id, plot.id, limit=5
            )
            context.extend(
                f"Pending task: {reminder.title} due {reminder.due_at.isoformat()}"
                for reminder in reminders
            )
            memories = await self._memory.search_plot(
                farmer_id=farmer_id,
                plot_id=plot.id,
                query=query,
                limit=5,
            )
            context.extend(f"Relevant plot memory: {fact.text}" for fact in memories)
        if chat.diagnosis_case_id is not None:
            case = await self._diagnoses.get_case(farmer_id, chat.diagnosis_case_id)
            if case is None:
                raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
            assessment = await self._diagnoses.get_active_assessment(farmer_id, case.id)
            if assessment:
                context.append(
                    f"Active diagnosis: {assessment.predicted_crop} / "
                    f"{assessment.primary_disease} ({assessment.confidence_label} confidence)"
                )
                predictions = await self._diagnoses.combined_predictions(assessment.id)
                context.extend(
                    f"Diagnosis alternative {item.rank}: {item.crop_name} / "
                    f"{item.disease_name} ({item.confidence:.1%})"
                    for item in predictions[:3]
                )
            images = await self._diagnoses.list_images(farmer_id, case.id)
            flags = sorted({flag for image in images for flag in image.quality_flags})
            context.append(
                f"Diagnosis images: {len(images)}; quality flags: {', '.join(flags) or 'none'}"
            )
        return context

    async def _validate_scope(
        self, farmer_id: UUID, data: ChatCreate
    ) -> tuple[UUID | None, UUID | None, UUID | None]:
        if data.farm_id is not None and await self._farms.get_farm(
            farmer_id, data.farm_id
        ) is None:
            raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
        if data.plot_id is not None:
            plot = await self._farms.get_plot(farmer_id, data.plot_id)
            if plot is None:
                raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
            if data.farm_id is not None and data.farm_id != plot.farm_id:
                raise ApplicationError(code="PLOT_NOT_IN_FARM", status_code=409)
        if data.diagnosis_case_id is not None:
            case = await self._diagnoses.get_case(farmer_id, data.diagnosis_case_id)
            if case is None:
                raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
            return case.farm_id, case.plot_id, case.id
        return data.farm_id, data.plot_id, None

    async def _chat(self, farmer_id: UUID, chat_id: UUID) -> ChatSession:
        chat = await self._repository.get_chat(farmer_id, chat_id)
        if chat is None:
            raise ApplicationError(code="CHAT_NOT_FOUND", status_code=404)
        return chat

    @staticmethod
    def _instructions(language: SupportedLanguage | None) -> str:
        language_code = language.value if language else "en"
        return (
            "You are a careful agricultural assistant for farmers. Respond in simple "
            f"farmer-friendly language using locale {language_code}. Lead with a short answer. "
            "Ask targeted follow-up questions when context is insufficient. Never invent facts, "
            "diagnoses, weather, product brands, or local approvals. Treatment detail must state "
            "uncertainty and safety precautions. A reminder may only be proposed, never claimed "
            "as created. When a plot forecast could affect guidance, call get_plot_forecast; "
            "do not invent or request different coordinates."
        )

    @staticmethod
    def _input(
        recent: list[ChatMessage], context: list[str], current_question: str
    ) -> str:
        recent_text = "\n".join(f"{item.role}: {item.content}" for item in recent)
        context_text = "\n".join(context) or "No farm, plot, scan, or long-term memory context."
        return (
            f"Allowed scoped context:\n{context_text}\n\n"
            f"Recent messages from this chat only:\n{recent_text}\n\n"
            f"Current farmer message:\n{current_question}"
        )

    @staticmethod
    def _local_title(content: str) -> str:
        words = content.split()
        title = " ".join(words[:8])
        return title[:147] + ("..." if len(title) > 147 else "")

    @staticmethod
    def _render_treatment(treatment: object) -> str:
        from app.integrations.llm.provider import TreatmentGuidance

        value = TreatmentGuidance.model_validate(treatment)
        lines = ["Treatment guidance:"]
        fields = (
            ("Active ingredient", value.active_ingredient),
            ("Dosage", value.dosage),
            ("Application", value.application_method),
            ("Frequency", value.frequency),
        )
        lines.extend(f"{label}: {item}" for label, item in fields if item)
        lines.extend(f"Safety: {item}" for item in value.safety_precautions)
        lines.append("Verify local approval and label guidance before use.")
        return "\n".join(lines)
