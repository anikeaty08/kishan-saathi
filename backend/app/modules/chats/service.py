"""Scoped chat lifecycle, context selection, and LLM coordination."""

from datetime import UTC, datetime
from uuid import UUID

from app.core.errors import ApplicationError
from app.integrations.llm.provider import LLMRequest, LLMTask
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
    ChatScope,
    ChatUpdate,
    SendMessageResponse,
)
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.users.schemas import SupportedLanguage


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
    ) -> None:
        self._repository = repository
        self._farms = farms
        self._diagnoses = diagnoses
        self._memory = memory
        self._llm = llm

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
        task = (
            LLMTask.AGRICULTURAL_GUIDANCE
            if chat.scope_type in {ChatScope.PLOT.value, ChatScope.SCAN.value}
            else LLMTask.ROUTINE_CHAT
        )
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
                )
            )
            content = result.reply.short_answer
            if result.reply.details:
                content = f"{content}\n\n{result.reply.details}"
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
            if chat.title == "New conversation":
                chat.title = self._local_title(data.content)
            await self._repository.commit()
        except Exception:
            await self._repository.rollback()
            raise
        await self._repository.refresh(user_message)
        await self._repository.refresh(assistant_message)
        return SendMessageResponse(
            user_message=ChatMessageResponse.model_validate(user_message),
            assistant_message=ChatMessageResponse.model_validate(assistant_message),
            reminder_proposal=result.reply.reminder_proposal,
        )

    async def _context(
        self, farmer_id: UUID, chat: ChatSession, query: str
    ) -> list[str]:
        context: list[str] = []
        if chat.plot_id is not None:
            plot = await self._farms.get_plot(farmer_id, chat.plot_id)
            if plot is None:
                raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
            context.extend(
                [
                    f"Plot: {plot.name}",
                    f"Coordinates: {plot.latitude}, {plot.longitude}",
                ]
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
            "as created."
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
