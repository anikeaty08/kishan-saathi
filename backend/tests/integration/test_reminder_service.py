"""Integration tests for reminder consent and recurring task behavior."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.errors import ApplicationError
from app.database.base import Base
from app.modules.chats.repository import ChatRepository
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.reminders.repository import ReminderRepository
from app.modules.reminders.schemas import (
    ProposalCreate,
    ReminderAction,
    ReminderActionRequest,
)
from app.modules.reminders.service import ReminderService
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-000000000021")
OTHER = UUID("00000000-0000-0000-0000-000000000022")


@pytest.mark.asyncio
async def test_proposal_requires_acceptance_and_recurring_task_rolls_forward() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with sessions() as session:
            session.add_all([_farmer(FARMER, "owner"), _farmer(OTHER, "other")])
            await session.commit()
            repository = ReminderRepository(session)
            service = ReminderService(
                repository=repository,
                farms=FarmRepository(session),
                diagnoses=DiagnosisRepository(session),
                chats=ChatRepository(session),
            )
            due_at = datetime.now(tz=UTC) + timedelta(days=2)
            proposal = await service.create_proposal(
                FARMER,
                ProposalCreate(
                    title="Inspect affected leaves",
                    due_at=due_at,
                    recurrence_days=3,
                ),
            )

            assert await service.list_reminders(FARMER, include_finished=False) == []
            with pytest.raises(ApplicationError) as hidden:
                await service.decide_proposal(OTHER, proposal.id, accepted=True)

            decision = await service.decide_proposal(FARMER, proposal.id, accepted=True)
            assert decision.proposal.status == "accepted"
            assert decision.reminder is not None
            reminder_id = decision.reminder.id

            with pytest.raises(ApplicationError) as repeated:
                await service.decide_proposal(FARMER, proposal.id, accepted=False)

            completed = await service.apply_action(
                FARMER,
                reminder_id,
                ReminderActionRequest(action=ReminderAction.DONE),
            )
            all_tasks = await service.list_reminders(FARMER, include_finished=True)
            pending = await service.list_reminders(FARMER, include_finished=False)
    finally:
        await engine.dispose()

    assert hidden.value.code == "REMINDER_PROPOSAL_NOT_FOUND"
    assert repeated.value.code == "REMINDER_PROPOSAL_ALREADY_DECIDED"
    assert completed.status == "done"
    assert len(all_tasks) == 2
    assert len(pending) == 1
    assert pending[0].status == "pending"
    assert pending[0].due_at.replace(tzinfo=UTC) == due_at + timedelta(days=3)


@pytest.mark.asyncio
async def test_declined_proposal_never_creates_task() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "owner"))
            await session.commit()
            service = ReminderService(
                repository=ReminderRepository(session),
                farms=FarmRepository(session),
                diagnoses=DiagnosisRepository(session),
                chats=ChatRepository(session),
            )
            proposal = await service.create_proposal(
                FARMER,
                ProposalCreate(
                    title="Check moisture",
                    due_at=datetime.now(tz=UTC) + timedelta(hours=4),
                ),
            )
            decision = await service.decide_proposal(FARMER, proposal.id, accepted=False)
            reminders = await service.list_reminders(FARMER, include_finished=True)
    finally:
        await engine.dispose()

    assert decision.proposal.status == "declined"
    assert decision.reminder is None
    assert reminders == []


@pytest.mark.asyncio
async def test_expired_proposal_cannot_create_an_overdue_task() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "expired"))
            await session.commit()
            repository = ReminderRepository(session)
            service = ReminderService(
                repository=repository,
                farms=FarmRepository(session),
                diagnoses=DiagnosisRepository(session),
                chats=ChatRepository(session),
            )
            proposal = await service.create_proposal(
                FARMER,
                ProposalCreate(
                    title="Inspect soon",
                    due_at=datetime.now(tz=UTC) + timedelta(hours=1),
                ),
            )
            stored = await repository.get_proposal(FARMER, proposal.id)
            assert stored is not None
            stored.due_at = datetime.now(tz=UTC) - timedelta(minutes=1)
            await repository.commit()

            with pytest.raises(ApplicationError) as raised:
                await service.decide_proposal(FARMER, proposal.id, accepted=True)
            pending = await service.list_proposals(FARMER, pending_only=True)
            reminders = await service.list_reminders(FARMER, include_finished=True)
    finally:
        await engine.dispose()

    assert raised.value.code == "REMINDER_PROPOSAL_EXPIRED"
    assert pending == []
    assert reminders == []


def _farmer(farmer_id: UUID, suffix: str) -> FarmerProfile:
    return FarmerProfile(
        id=farmer_id,
        cognito_sub=suffix,
        cognito_username=f"{suffix}@example.com",
        email=f"{suffix}@example.com",
    )
