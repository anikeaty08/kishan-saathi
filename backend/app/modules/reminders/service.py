"""Controlled reminder proposals, confirmations, and outcomes."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from app.core.errors import ApplicationError
from app.modules.chats.repository import ChatRepository
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.reminders.models import Reminder, ReminderProposal
from app.modules.reminders.repository import ReminderRepository
from app.modules.reminders.schemas import (
    ProposalCreate,
    ProposalDecisionResponse,
    ProposalResponse,
    ReminderAction,
    ReminderActionRequest,
    ReminderCreate,
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
        await self._validate_links(
            farmer_id,
            plot_id=data.plot_id,
            crop_id=data.crop_id,
            diagnosis_case_id=data.diagnosis_case_id,
            chat_id=data.chat_id,
        )
        proposal = ReminderProposal(
            farmer_id=farmer_id,
            **data.model_dump(),
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
        proposal.status = "accepted" if accepted else "declined"
        proposal.decided_at = datetime.now(tz=UTC)
        reminder: Reminder | None = None
        if accepted:
            reminder = Reminder(
                farmer_id=farmer_id,
                proposal_id=proposal.id,
                chat_id=proposal.chat_id,
                diagnosis_case_id=proposal.diagnosis_case_id,
                plot_id=proposal.plot_id,
                crop_id=proposal.crop_id,
                title=proposal.title,
                due_at=proposal.due_at,
                recurrence_days=proposal.recurrence_days,
                status="pending",
            )
            self._repository.add(reminder)
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
        await self._validate_links(
            farmer_id,
            plot_id=data.plot_id,
            crop_id=data.crop_id,
            diagnosis_case_id=data.diagnosis_case_id,
            chat_id=None,
        )
        reminder = Reminder(farmer_id=farmer_id, **data.model_dump(), status="pending")
        self._repository.add(reminder)
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
                farmer_id=farmer_id,
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
        await self._repository.commit()
        await self._repository.refresh(reminder)
        return ReminderResponse.model_validate(reminder)

    async def _validate_links(
        self,
        farmer_id: UUID,
        *,
        plot_id: UUID | None,
        crop_id: UUID | None,
        diagnosis_case_id: UUID | None,
        chat_id: UUID | None,
    ) -> None:
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
        if diagnosis_case_id is not None and await self._diagnoses.get_case(
            farmer_id, diagnosis_case_id
        ) is None:
            raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
        if chat_id is not None and await self._chats.get_chat(farmer_id, chat_id) is None:
            raise ApplicationError(code="CHAT_NOT_FOUND", status_code=404)
