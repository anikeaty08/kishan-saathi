"""Owner-scoped persistence for farm organization."""

from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.chats.models import ChatSession
from app.modules.diagnoses.models import DiagnosisCase
from app.modules.farms.models import Activity, ActivityPhoto, Crop, CropStageEvent, Farm, Plot
from app.modules.memories.models import ChatMemoryConnection, ScopedMemoryFact
from app.modules.reminders.models import Reminder, ReminderProposal


class FarmRepository:
    """All reads include the authenticated farmer owner key."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list_farms(self, farmer_id: UUID) -> list[Farm]:
        result = await self.session.scalars(
            select(Farm).where(Farm.farmer_id == farmer_id).order_by(Farm.name)
        )
        return list(result)

    async def get_farm(self, farmer_id: UUID, farm_id: UUID) -> Farm | None:
        result = await self.session.execute(
            select(Farm).where(Farm.id == farm_id, Farm.farmer_id == farmer_id)
        )
        return result.scalar_one_or_none()

    async def farm_plot_count(self, farmer_id: UUID, farm_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.count()).select_from(Plot).where(
                Plot.farmer_id == farmer_id, Plot.farm_id == farm_id
            )
        )
        return int(value or 0)

    async def farm_linked_record_counts(
        self, farmer_id: UUID, farm_id: UUID
    ) -> dict[str, int]:
        queries = {
            "plots": select(func.count()).select_from(Plot).where(
                Plot.farmer_id == farmer_id, Plot.farm_id == farm_id
            ),
            "chats": select(func.count()).select_from(ChatSession).where(
                ChatSession.farmer_id == farmer_id, ChatSession.farm_id == farm_id
            ),
            "diagnoses": select(func.count()).select_from(DiagnosisCase).where(
                DiagnosisCase.farmer_id == farmer_id, DiagnosisCase.farm_id == farm_id
            ),
            "memories": select(func.count()).select_from(ScopedMemoryFact).where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.farm_id == farm_id,
            ),
            "connected_chats": select(func.count()).select_from(ChatMemoryConnection).where(
                ChatMemoryConnection.farmer_id == farmer_id,
                ChatMemoryConnection.farm_id == farm_id,
            ),
        }
        return {
            name: int(await self.session.scalar(statement) or 0)
            for name, statement in queries.items()
        }

    async def list_plots(self, farmer_id: UUID, farm_id: UUID | None) -> list[Plot]:
        statement = select(Plot).where(Plot.farmer_id == farmer_id)
        if farm_id is not None:
            statement = statement.where(Plot.farm_id == farm_id)
        result = await self.session.scalars(statement.order_by(Plot.name))
        return list(result)

    async def get_plot(self, farmer_id: UUID, plot_id: UUID) -> Plot | None:
        result = await self.session.execute(
            select(Plot).where(Plot.id == plot_id, Plot.farmer_id == farmer_id)
        )
        return result.scalar_one_or_none()

    async def list_crops(self, farmer_id: UUID, plot_id: UUID) -> list[Crop]:
        result = await self.session.scalars(
            select(Crop)
            .where(Crop.farmer_id == farmer_id, Crop.plot_id == plot_id)
            .order_by(Crop.created_at)
        )
        return list(result)

    async def list_activities(
        self, farmer_id: UUID, plot_id: UUID, *, limit: int = 10
    ) -> list[Activity]:
        result = await self.session.scalars(
            select(Activity)
            .where(Activity.farmer_id == farmer_id, Activity.plot_id == plot_id)
            .order_by(Activity.occurred_at.desc())
            .limit(limit)
        )
        return list(result)

    async def get_crop(
        self, farmer_id: UUID, crop_id: UUID, *, for_update: bool = False
    ) -> Crop | None:
        statement = select(Crop).where(
            Crop.id == crop_id, Crop.farmer_id == farmer_id
        )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement)
        return result.scalar_one_or_none()

    async def get_activity(self, farmer_id: UUID, activity_id: UUID) -> Activity | None:
        result = await self.session.execute(
            select(Activity).where(
                Activity.id == activity_id, Activity.farmer_id == farmer_id
            )
        )
        return result.scalar_one_or_none()

    async def list_activity_photos(
        self, farmer_id: UUID, activity_id: UUID
    ) -> list[ActivityPhoto]:
        result = await self.session.scalars(
            select(ActivityPhoto)
            .where(
                ActivityPhoto.farmer_id == farmer_id,
                ActivityPhoto.activity_id == activity_id,
            )
            .order_by(ActivityPhoto.created_at)
        )
        return list(result)

    async def get_activity_photo(
        self, farmer_id: UUID, activity_id: UUID, photo_id: UUID
    ) -> ActivityPhoto | None:
        result = await self.session.execute(
            select(ActivityPhoto).where(
                ActivityPhoto.id == photo_id,
                ActivityPhoto.activity_id == activity_id,
                ActivityPhoto.farmer_id == farmer_id,
            )
        )
        return result.scalar_one_or_none()

    async def plot_activity_count(self, farmer_id: UUID, plot_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.count()).select_from(Activity).where(
                Activity.farmer_id == farmer_id, Activity.plot_id == plot_id
            )
        )
        return int(value or 0)

    async def crop_activity_count(self, farmer_id: UUID, crop_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.count()).select_from(Activity).where(
                Activity.farmer_id == farmer_id, Activity.crop_id == crop_id
            )
        )
        return int(value or 0)

    async def plot_linked_record_counts(
        self, farmer_id: UUID, plot_id: UUID
    ) -> dict[str, int]:
        queries = {
            "crops": select(func.count()).select_from(Crop).where(
                Crop.farmer_id == farmer_id, Crop.plot_id == plot_id
            ),
            "activities": select(func.count()).select_from(Activity).where(
                Activity.farmer_id == farmer_id, Activity.plot_id == plot_id
            ),
            "diagnoses": select(func.count()).select_from(DiagnosisCase).where(
                DiagnosisCase.farmer_id == farmer_id, DiagnosisCase.plot_id == plot_id
            ),
            "chats": select(func.count()).select_from(ChatSession).where(
                ChatSession.farmer_id == farmer_id, ChatSession.plot_id == plot_id
            ),
            "reminders": select(func.count()).select_from(Reminder).where(
                Reminder.farmer_id == farmer_id, Reminder.plot_id == plot_id
            ),
            "reminder_proposals": select(func.count()).select_from(ReminderProposal).where(
                ReminderProposal.farmer_id == farmer_id,
                ReminderProposal.plot_id == plot_id,
            ),
            "memories": select(func.count()).select_from(ScopedMemoryFact).where(
                ScopedMemoryFact.farmer_id == farmer_id,
                ScopedMemoryFact.plot_id == plot_id,
            ),
            "connected_chats": select(func.count()).select_from(ChatMemoryConnection).where(
                ChatMemoryConnection.farmer_id == farmer_id,
                ChatMemoryConnection.plot_id == plot_id,
            ),
        }
        return {
            name: int(await self.session.scalar(statement) or 0)
            for name, statement in queries.items()
        }

    async def crop_linked_record_counts(
        self, farmer_id: UUID, crop_id: UUID
    ) -> dict[str, int]:
        queries = {
            "activities": select(func.count()).select_from(Activity).where(
                Activity.farmer_id == farmer_id, Activity.crop_id == crop_id
            ),
            "diagnoses": select(func.count()).select_from(DiagnosisCase).where(
                DiagnosisCase.farmer_id == farmer_id, DiagnosisCase.crop_id == crop_id
            ),
            "reminders": select(func.count()).select_from(Reminder).where(
                Reminder.farmer_id == farmer_id, Reminder.crop_id == crop_id
            ),
            "reminder_proposals": select(func.count()).select_from(ReminderProposal).where(
                ReminderProposal.farmer_id == farmer_id,
                ReminderProposal.crop_id == crop_id,
            ),
        }
        return {
            name: int(await self.session.scalar(statement) or 0)
            for name, statement in queries.items()
        }

    def add(
        self, value: Farm | Plot | Crop | CropStageEvent | Activity | ActivityPhoto
    ) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def refresh(
        self, value: Farm | Plot | Crop | CropStageEvent | Activity | ActivityPhoto
    ) -> None:
        await self.session.refresh(value)

    async def delete(self, value: Farm | Plot | Crop | Activity | ActivityPhoto) -> None:
        await self.session.delete(value)
