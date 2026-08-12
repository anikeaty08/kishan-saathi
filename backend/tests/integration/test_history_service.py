"""Integration tests for immutable reminder events and combined timelines."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.database.base import Base
from app.modules.chats.repository import ChatRepository
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.models import Activity, Crop, CropStageEvent, Farm, Plot
from app.modules.farms.repository import FarmRepository
from app.modules.history.repository import HistoryRepository
from app.modules.history.schemas import TimelineCategory, TimelineQuery
from app.modules.history.service import HistoryService
from app.modules.reminders.repository import ReminderRepository
from app.modules.reminders.schemas import ReminderAction, ReminderActionRequest, ReminderCreate
from app.modules.reminders.service import ReminderService
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-000000000071")


@pytest.mark.asyncio
async def test_reschedule_preserves_old_date_and_timeline_filters() -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    now = datetime.now(tz=UTC)

    try:
        async with sessions() as session:
            session.add(_farmer())
            farm = Farm(farmer_id=FARMER, name="History Farm")
            session.add(farm)
            await session.flush()
            plot = Plot(
                farmer_id=FARMER,
                farm_id=farm.id,
                name="History Plot",
                latitude=20,
                longitude=75,
            )
            session.add(plot)
            await session.flush()
            crop = Crop(farmer_id=FARMER, plot_id=plot.id, name="Rice", stage="seedling")
            session.add(crop)
            await session.flush()
            session.add_all(
                [
                    CropStageEvent(
                        farmer_id=FARMER,
                        crop_id=crop.id,
                        stage="seedling",
                        observed_at=now - timedelta(days=2),
                    ),
                    Activity(
                        farmer_id=FARMER,
                        plot_id=plot.id,
                        crop_id=crop.id,
                        title="Irrigation completed",
                        occurred_at=now - timedelta(days=1),
                    ),
                ]
            )
            await session.commit()
            reminders = ReminderService(
                ReminderRepository(session),
                FarmRepository(session),
                DiagnosisRepository(session),
                ChatRepository(session),
            )
            original_due_at = now + timedelta(days=2)
            reminder = await reminders.create_manual(
                FARMER,
                ReminderCreate(
                    plot_id=plot.id,
                    crop_id=crop.id,
                    title="Inspect leaves",
                    due_at=original_due_at,
                ),
            )
            new_due_at = now + timedelta(days=4)
            await reminders.apply_action(
                FARMER,
                reminder.id,
                ReminderActionRequest(
                    action=ReminderAction.RESCHEDULE,
                    due_at=new_due_at,
                ),
            )
            events = await reminders.list_events(FARMER, reminder.id)
            history = HistoryService(HistoryRepository(session), FarmRepository(session))
            page = await history.timeline(
                FARMER,
                plot.id,
                query=TimelineQuery(
                    crop_id=crop.id,
                    categories={TimelineCategory.REMINDER},
                    limit=20,
                ),
            )
    finally:
        await engine.dispose()

    assert [event.event_type for event in events] == ["scheduled", "rescheduled"]
    assert events[1].previous_due_at is not None
    assert events[1].previous_due_at.replace(tzinfo=UTC) == original_due_at
    assert events[1].due_at.replace(tzinfo=UTC) == new_due_at
    assert {item.event_code for item in page.items} == {
        "reminder.scheduled",
        "reminder.rescheduled",
    }


def _farmer() -> FarmerProfile:
    return FarmerProfile(
        id=FARMER,
        cognito_sub="history",
        cognito_username="history@example.com",
        email="history@example.com",
    )
