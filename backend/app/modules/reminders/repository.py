"""Owner-scoped reminder persistence."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.reminders.models import Reminder, ReminderProposal


class ReminderRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_proposal(
        self, farmer_id: UUID, proposal_id: UUID, *, for_update: bool = False
    ) -> ReminderProposal | None:
        statement = select(ReminderProposal).where(
            ReminderProposal.id == proposal_id,
            ReminderProposal.farmer_id == farmer_id,
        )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement)
        return result.scalar_one_or_none()

    async def get_reminder(
        self, farmer_id: UUID, reminder_id: UUID, *, for_update: bool = False
    ) -> Reminder | None:
        statement = select(Reminder).where(
            Reminder.id == reminder_id, Reminder.farmer_id == farmer_id
        )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement)
        return result.scalar_one_or_none()

    async def list_reminders(
        self, farmer_id: UUID, *, include_finished: bool
    ) -> list[Reminder]:
        statement = select(Reminder).where(Reminder.farmer_id == farmer_id)
        if not include_finished:
            statement = statement.where(Reminder.status == "pending")
        result = await self.session.scalars(statement.order_by(Reminder.due_at))
        return list(result)

    async def list_plot_pending(
        self, farmer_id: UUID, plot_id: UUID, *, limit: int = 10
    ) -> list[Reminder]:
        result = await self.session.scalars(
            select(Reminder)
            .where(
                Reminder.farmer_id == farmer_id,
                Reminder.plot_id == plot_id,
                Reminder.status == "pending",
            )
            .order_by(Reminder.due_at)
            .limit(limit)
        )
        return list(result)

    def add(self, value: Reminder | ReminderProposal) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def refresh(self, value: Reminder | ReminderProposal) -> None:
        await self.session.refresh(value)

    async def flush(self) -> None:
        await self.session.flush()
