"""Private activity-photo lifecycle."""

from uuid import UUID

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.storage.provider import ObjectStorageProvider
from app.modules.diagnoses.images import ImagePreprocessor
from app.modules.farms.models import ActivityPhoto
from app.modules.farms.repository import FarmRepository
from app.modules.farms.schemas import ActivityPhotoResponse
from app.modules.storage_cleanup.service import ObjectCleanupService


class ActivityPhotoService:
    def __init__(
        self,
        *,
        settings: Settings,
        repository: FarmRepository,
        storage: ObjectStorageProvider,
        cleanup: ObjectCleanupService,
    ) -> None:
        self._repository = repository
        self._storage = storage
        self._cleanup = cleanup
        self._preprocessor = ImagePreprocessor(settings, error_prefix="ACTIVITY_PHOTO")

    async def add(
        self, farmer_id: UUID, activity_id: UUID, content: bytes
    ) -> ActivityPhotoResponse:
        await self._activity(farmer_id, activity_id)
        prepared = await self._preprocessor.prepare(content)
        stored = await self._storage.put_private_image(
            owner_id=farmer_id,
            category="activity-photos",
            content=prepared.content,
        )
        photo = ActivityPhoto(
            farmer_id=farmer_id,
            activity_id=activity_id,
            object_key=stored.key,
            size_bytes=stored.size_bytes,
            width=prepared.width,
            height=prepared.height,
        )
        self._repository.add(photo)
        try:
            await self._repository.commit()
        except Exception:
            await self._repository.session.rollback()
            job = self._cleanup.enqueue(farmer_id, stored.key, "activity_photo_create_rollback")
            await self._repository.commit()
            await self._cleanup.process([job.id])
            raise
        await self._repository.refresh(photo)
        return ActivityPhotoResponse.model_validate(photo)

    async def list(self, farmer_id: UUID, activity_id: UUID) -> list[ActivityPhotoResponse]:
        await self._activity(farmer_id, activity_id)
        return [
            ActivityPhotoResponse.model_validate(photo)
            for photo in await self._repository.list_activity_photos(farmer_id, activity_id)
        ]

    async def read(self, farmer_id: UUID, activity_id: UUID, photo_id: UUID) -> bytes:
        photo = await self._photo(farmer_id, activity_id, photo_id)
        return await self._storage.read_private(owner_id=farmer_id, key=photo.object_key)

    async def delete(self, farmer_id: UUID, activity_id: UUID, photo_id: UUID) -> None:
        photo = await self._photo(farmer_id, activity_id, photo_id)
        object_key = photo.object_key
        job = self._cleanup.enqueue(farmer_id, object_key, "activity_photo_deleted")
        await self._repository.delete(photo)
        await self._repository.commit()
        await self._cleanup.process([job.id])

    async def delete_activity(self, farmer_id: UUID, activity_id: UUID) -> None:
        activity = await self._repository.get_activity(farmer_id, activity_id)
        if activity is None:
            raise ApplicationError(code="ACTIVITY_NOT_FOUND", status_code=404)
        photos = await self._repository.list_activity_photos(farmer_id, activity_id)
        jobs = [
            self._cleanup.enqueue(farmer_id, photo.object_key, "activity_deleted")
            for photo in photos
        ]
        await self._repository.delete(activity)
        await self._repository.commit()
        await self._cleanup.process([job.id for job in jobs])

    async def _activity(self, farmer_id: UUID, activity_id: UUID) -> None:
        if await self._repository.get_activity(farmer_id, activity_id) is None:
            raise ApplicationError(code="ACTIVITY_NOT_FOUND", status_code=404)

    async def _photo(self, farmer_id: UUID, activity_id: UUID, photo_id: UUID) -> ActivityPhoto:
        await self._activity(farmer_id, activity_id)
        photo = await self._repository.get_activity_photo(farmer_id, activity_id, photo_id)
        if photo is None:
            raise ApplicationError(code="ACTIVITY_PHOTO_NOT_FOUND", status_code=404)
        return photo
