"""Controlled reminder proposals, confirmations, and outcomes."""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from app.core.errors import ApplicationError
from app.modules.chats.repository import ChatRepository
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.reminders.models import Reminder, ReminderEvent, ReminderProposal
from app.modules.reminders.repository import ReminderRepository
from app.modules.reminders.schemas import (
    ProposalCreate,
    ProposalDecisionResponse,
    ProposalResponse,
    ReminderAction,
    ReminderActionRequest,
    ReminderCreate,
    ReminderEventResponse,
    ReminderResponse,
)


class ReminderService:
    """Ensure AI proposals cannot become tasks without farmer confirmation."""

    def __init__(
        self,
        repository: ReminderRepository,
        farms: FarmRepository,
        diagnoses: DiagnosisRepository,
        chats: ChatRepository,
    ) -> None:
        self._repository = repository
        self._farms = farms
        self._diagnoses = diagnoses
        self._chats = chats

    async def create_proposal(
        self, farmer_id: UUID, data: ProposalCreate
    ) -> ProposalResponse:
        plot_id, crop_id = await self._validate_links(
            farmer_id,
            plot_id=data.plot_id,
            crop_id=data.crop_id,
            diagnosis_case_id=data.diagnosis_case_id,
            chat_id=data.chat_id,
        )
        proposal = ReminderProposal(
            farmer_id=farmer_id,
            **data.model_dump(exclude={"plot_id", "crop_id"}),
            plot_id=plot_id,
            crop_id=crop_id,
            status="pending",
        )
        self._repository.add(proposal)
        await self._repository.commit()
        await self._repository.refresh(proposal)
        return ProposalResponse.model_validate(proposal)

    async def decide_proposal(
        self, farmer_id: UUID, proposal_id: UUID, *, accepted: bool
    ) -> ProposalDecisionResponse:
        proposal = await self._repository.get_proposal(
            farmer_id, proposal_id, for_update=True
        )
        if proposal is None:
            raise ApplicationError(code="REMINDER_PROPOSAL_NOT_FOUND", status_code=404)
        if proposal.status != "pending":
            raise ApplicationError(code="REMINDER_PROPOSAL_ALREADY_DECIDED", status_code=409)
        canonical_plot_id, canonical_crop_id = await self._validate_links(
            farmer_id,
            plot_id=proposal.plot_id,
            crop_id=proposal.crop_id,
            diagnosis_case_id=proposal.diagnosis_case_id,
            chat_id=proposal.chat_id,
        )
        proposal.status = "accepted" if accepted else "declined"
        proposal.decided_at = datetime.now(tz=UTC)
        reminder: Reminder | None = None
        if accepted:
            reminder = Reminder(
                id=uuid4(),
                series_id=uuid4(),
                farmer_id=farmer_id,
                proposal_id=proposal.id,
                chat_id=proposal.chat_id,
                diagnosis_case_id=proposal.diagnosis_case_id,
                plot_id=canonical_plot_id,
                crop_id=canonical_crop_id,
                title=proposal.title,
                due_at=proposal.due_at,
                recurrence_days=proposal.recurrence_days,
                status="pending",
            )
            self._repository.add(reminder)
            self._repository.add(self._event(reminder, "scheduled", proposal.decided_at))
        await self._repository.commit()
        await self._repository.refresh(proposal)
        if reminder:
            await self._repository.refresh(reminder)
        return ProposalDecisionResponse(
            proposal=ProposalResponse.model_validate(proposal),
            reminder=ReminderResponse.model_validate(reminder) if reminder else None,
        )

    async def create_manual(
        self, farmer_id: UUID, data: ReminderCreate
    ) -> ReminderResponse:
        plot_id, crop_id = await self._validate_links(
            farmer_id,
            plot_id=data.plot_id,
            crop_id=data.crop_id,
            diagnosis_case_id=data.diagnosis_case_id,
            chat_id=None,
        )
        reminder = Reminder(
            id=uuid4(),
            series_id=uuid4(),
            farmer_id=farmer_id,
            **data.model_dump(exclude={"plot_id", "crop_id"}),
            plot_id=plot_id,
            crop_id=crop_id,
            status="pending",
        )
        self._repository.add(reminder)
        self._repository.add(self._event(reminder, "scheduled"))
        await self._repository.commit()
        await self._repository.refresh(reminder)
        return ReminderResponse.model_validate(reminder)

    async def list_reminders(
        self, farmer_id: UUID, *, include_finished: bool
    ) -> list[ReminderResponse]:
        values = await self._repository.list_reminders(
            farmer_id, include_finished=include_finished
        )
        return [ReminderResponse.model_validate(value) for value in values]

    async def apply_action(
        self,
        farmer_id: UUID,
        reminder_id: UUID,
        data: ReminderActionRequest,
    ) -> ReminderResponse:
        reminder = await self._repository.get_reminder(
            farmer_id, reminder_id, for_update=True
        )
        if reminder is None:
            raise ApplicationError(code="REMINDER_NOT_FOUND", status_code=404)
        if reminder.status != "pending":
            raise ApplicationError(code="REMINDER_ALREADY_FINISHED", status_code=409)
        now = datetime.now(tz=UTC)
        previous_due_at = reminder.due_at
        if data.action is ReminderAction.RESCHEDULE:
            reminder.due_at = data.due_at or reminder.due_at
        elif data.action is ReminderAction.DONE:
            reminder.status = "done"
            reminder.completed_at = now
        elif data.action is ReminderAction.SKIP:
            reminder.status = "skipped"
            reminder.completed_at = now
        else:
            reminder.status = "cancelled"
            reminder.completed_at = now
        self._repository.add(
            self._event(
                reminder,
                {
                    ReminderAction.DONE: "done",
                    ReminderAction.SKIP: "skipped",
                    ReminderAction.RESCHEDULE: "rescheduled",
                    ReminderAction.CANCEL: "cancelled",
                }[data.action],
                now,
                previous_due_at=(
                    previous_due_at
                    if data.action is ReminderAction.RESCHEDULE
                    else None
                ),
            )
        )
        if (
            data.action in {ReminderAction.DONE, ReminderAction.SKIP}
            and reminder.recurrence_days
        ):
            reminder_due_at = reminder.due_at
            if reminder_due_at.tzinfo is None:
                reminder_due_at = reminder_due_at.replace(tzinfo=UTC)
            next_due_at = reminder_due_at + timedelta(days=reminder.recurrence_days)
            while next_due_at <= now:
                next_due_at += timedelta(days=reminder.recurrence_days)
            next_reminder = Reminder(
                id=uuid4(),
                farmer_id=farmer_id,
                series_id=reminder.series_id,
                parent_reminder_id=reminder.id,
                chat_id=reminder.chat_id,
                diagnosis_case_id=reminder.diagnosis_case_id,
                plot_id=reminder.plot_id,
                crop_id=reminder.crop_id,
                title=reminder.title,
                notes=reminder.notes,
                due_at=next_due_at,
                recurrence_days=reminder.recurrence_days,
                status="pending",
            )
            self._repository.add(next_reminder)
            self._repository.add(self._event(next_reminder, "scheduled", now))
        await self._repository.commit()
        await self._repository.refresh(reminder)
        return ReminderResponse.model_validate(reminder)

    async def list_events(
        self, farmer_id: UUID, reminder_id: UUID
    ) -> list[ReminderEventResponse]:
        if await self._repository.get_reminder(farmer_id, reminder_id) is None:
            raise ApplicationError(code="REMINDER_NOT_FOUND", status_code=404)
        return [
            ReminderEventResponse.model_validate(event)
            for event in await self._repository.list_events(farmer_id, reminder_id)
        ]

    @staticmethod
    def _event(
        reminder: Reminder,
        event_type: str,
        occurred_at: datetime | None = None,
        *,
        previous_due_at: datetime | None = None,
    ) -> ReminderEvent:
        return ReminderEvent(
            farmer_id=reminder.farmer_id,
            reminder_id=reminder.id,
            series_id=reminder.series_id,
            chat_id=reminder.chat_id,
            diagnosis_case_id=reminder.diagnosis_case_id,
            plot_id=reminder.plot_id,
            crop_id=reminder.crop_id,
            event_type=event_type,
            previous_due_at=previous_due_at,
            due_at=reminder.due_at,
            occurred_at=occurred_at or datetime.now(tz=UTC),
        )

    async def _validate_links(
        self,
        farmer_id: UUID,
        *,
        plot_id: UUID | None,
        crop_id: UUID | None,
        diagnosis_case_id: UUID | None,
        chat_id: UUID | None,
    ) -> tuple[UUID | None, UUID | None]:
        canonical_plot_id = plot_id
        canonical_crop_id = crop_id
        if plot_id is not None:
            plot = await self._farms.get_plot(farmer_id, plot_id)
            if plot is None:
                raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        if crop_id is not None:
            crop = await self._farms.get_crop(farmer_id, crop_id)
            if crop is None:
                raise ApplicationError(code="CROP_NOT_FOUND", status_code=404)
            if plot_id is not None and crop.plot_id != plot_id:
                raise ApplicationError(code="CROP_NOT_IN_PLOT", status_code=409)
            canonical_plot_id = crop.plot_id
        if diagnosis_case_id is not None:
            case = await self._diagnoses.get_case(farmer_id, diagnosis_case_id)
            if case is None:
                raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
            if canonical_plot_id is not None and case.plot_id != canonical_plot_id:
                raise ApplicationError(code="DIAGNOSIS_NOT_IN_PLOT", status_code=409)
            if canonical_crop_id is not None and case.crop_id != canonical_crop_id:
                raise ApplicationError(code="DIAGNOSIS_NOT_IN_CROP", status_code=409)
            canonical_plot_id = case.plot_id or canonical_plot_id
            canonical_crop_id = case.crop_id or canonical_crop_id
        if chat_id is not None:
            chat = await self._chats.get_chat(farmer_id, chat_id)
            if chat is None:
                raise ApplicationError(code="CHAT_NOT_FOUND", status_code=404)
            if chat.diagnosis_case_id is not None:
                case = await self._diagnoses.get_case(farmer_id, chat.diagnosis_case_id)
                if case is None:
                    raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
                chat_plot_id = case.plot_id
                chat_crop_id = case.crop_id
            else:
                chat_plot_id = chat.plot_id
                chat_crop_id = None
            if diagnosis_case_id is not None and chat.diagnosis_case_id != diagnosis_case_id:
                raise ApplicationError(code="CHAT_NOT_IN_DIAGNOSIS", status_code=409)
            if chat.scope_type == "farm" and canonical_plot_id is not None:
                plot = await self._farms.get_plot(farmer_id, canonical_plot_id)
                if plot is None or plot.farm_id != chat.farm_id:
                    raise ApplicationError(code="CHAT_NOT_IN_FARM", status_code=409)
            if (
                canonical_plot_id is not None
                and chat_plot_id != canonical_plot_id
                and chat.scope_type != "farm"
            ):
                raise ApplicationError(code="CHAT_NOT_IN_PLOT", status_code=409)
            if (
                canonical_crop_id is not None
                and chat_crop_id is not None
                and chat_crop_id != canonical_crop_id
            ):
                raise ApplicationError(code="CHAT_NOT_IN_CROP", status_code=409)
            canonical_plot_id = chat_plot_id or canonical_plot_id
            canonical_crop_id = chat_crop_id or canonical_crop_id
        return canonical_plot_id, canonical_crop_id
