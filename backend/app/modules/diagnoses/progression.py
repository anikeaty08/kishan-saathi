"""Owner-scoped orchestration for visible symptom progression comparison."""

from datetime import UTC, datetime
from uuid import UUID

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.progression.provider import (
    ProgressionImage,
    ProgressionProvider,
    ProgressionRequest,
)
from app.integrations.storage.provider import ObjectStorageProvider
from app.modules.diagnoses.models import DiagnosisAssessment, DiagnosisImage
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.diagnoses.schemas import (
    ProgressionComparisonRequest,
    ProgressionComparisonResponse,
)

_BLOCKING_QUALITY_FLAGS = frozenset(
    {
        "too_small",
        "blurry",
        "very_blurry",
        "underexposed",
        "overexposed",
        "extreme_aspect_ratio",
        "not_a_leaf",
    }
)


class DiagnosisProgressionService:
    """Validate history and limits before sending private bytes to the provider."""

    def __init__(
        self,
        *,
        settings: Settings,
        repository: DiagnosisRepository,
        storage: ObjectStorageProvider,
        provider: ProgressionProvider,
    ) -> None:
        self._settings = settings
        self._repository = repository
        self._storage = storage
        self._provider = provider

    async def compare(
        self,
        farmer_id: UUID,
        case_id: UUID,
        selection: ProgressionComparisonRequest,
    ) -> ProgressionComparisonResponse:
        # Owner scoping happens before provider work, and returns the same opaque 404 as case APIs.
        if await self._repository.get_case(farmer_id, case_id) is None:
            raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)

        earlier, later = await self._timepoints(farmer_id, case_id, selection)
        earlier_images = await self._repository.assessment_images(
            farmer_id, case_id, earlier.id
        )
        later_images = await self._repository.assessment_images(farmer_id, case_id, later.id)
        earlier_images = self._usable_timepoint_images(earlier_images, "EARLIER")
        later_images = self._usable_timepoint_images(later_images, "LATER")
        if max(item.captured_or_uploaded_at for item in earlier_images) >= min(
            item.captured_or_uploaded_at for item in later_images
        ):
            raise ApplicationError(code="PROGRESSION_TIMEPOINT_ORDER_INVALID", status_code=422)

        earlier_images = earlier_images[: self._settings.progression_max_images_per_timepoint]
        later_images = later_images[: self._settings.progression_max_images_per_timepoint]
        selected_images = [*earlier_images, *later_images]
        if any(image.size_bytes > self._settings.max_image_bytes for image in selected_images):
            raise ApplicationError(code="PROGRESSION_IMAGE_INVALID", status_code=422)
        if sum(image.size_bytes for image in selected_images) > (
            self._settings.progression_max_total_image_bytes
        ):
            raise ApplicationError(code="PROGRESSION_IMAGES_TOO_LARGE", status_code=413)
        earlier_payload = await self._load_images(farmer_id, earlier_images)
        later_payload = await self._load_images(farmer_id, later_images)
        if sum(len(image.content) for image in (*earlier_payload, *later_payload)) > (
            self._settings.progression_max_total_image_bytes
        ):
            raise ApplicationError(code="PROGRESSION_IMAGES_TOO_LARGE", status_code=413)

        result = await self._provider.compare(
            ProgressionRequest(
                farmer_id=farmer_id,
                earlier_images=earlier_payload,
                later_images=later_payload,
                response_language=selection.response_language.value,
            )
        )
        return ProgressionComparisonResponse(
            case_id=case_id,
            earlier_assessment_id=earlier.id,
            later_assessment_id=later.id,
            earlier_captured_at=min(item.captured_or_uploaded_at for item in earlier_images),
            later_captured_at=max(item.captured_or_uploaded_at for item in later_images),
            earlier_image_ids=[item.id for item in earlier_images],
            later_image_ids=[item.id for item in later_images],
            trend=result.analysis.trend,
            confidence=result.analysis.confidence,
            summary=result.analysis.summary,
            evidence=result.analysis.evidence,
            limitations=result.analysis.limitations,
            image_quality=result.analysis.image_quality,
            model_name=result.model,
            generated_at=datetime.now(tz=UTC),
        )

    async def _timepoints(
        self,
        farmer_id: UUID,
        case_id: UUID,
        selection: ProgressionComparisonRequest,
    ) -> tuple[DiagnosisAssessment, DiagnosisAssessment]:
        if selection.earlier_assessment_id is not None:
            assert selection.later_assessment_id is not None
            earlier = await self._repository.get_assessment(
                farmer_id, case_id, selection.earlier_assessment_id
            )
            later = await self._repository.get_assessment(
                farmer_id, case_id, selection.later_assessment_id
            )
            if earlier is None or later is None:
                raise ApplicationError(code="PROGRESSION_TIMEPOINT_NOT_FOUND", status_code=404)
        else:
            newest = await self._repository.list_assessments(
                farmer_id,
                case_id,
                limit=self._settings.progression_history_scan_limit,
            )
            valid: list[tuple[datetime, DiagnosisAssessment]] = []
            for assessment in newest:
                images = await self._repository.assessment_images(
                    farmer_id, case_id, assessment.id
                )
                if images:
                    valid.append(
                        (
                            max(image.captured_or_uploaded_at for image in images),
                            assessment,
                        )
                    )
            if len(valid) < 2:
                raise ApplicationError(code="PROGRESSION_HISTORY_INSUFFICIENT", status_code=422)
            valid.sort(key=lambda item: item[0], reverse=True)
            later, earlier = valid[0][1], valid[1][1]

        return earlier, later

    def _usable_timepoint_images(
        self, images: list[DiagnosisImage], label: str
    ) -> list[DiagnosisImage]:
        if not images:
            raise ApplicationError(code="PROGRESSION_HISTORY_INSUFFICIENT", status_code=422)
        usable = [image for image in images if self._is_usable(image)]
        if not usable:
            raise ApplicationError(
                code="PROGRESSION_IMAGE_QUALITY_INSUFFICIENT",
                status_code=422,
                details=[{"timepoint": label}],
            )
        return usable

    def _is_usable(self, image: DiagnosisImage) -> bool:
        if min(image.width, image.height) < self._settings.progression_min_image_dimension:
            return False
        if image.quality_score is not None and (
            image.quality_score < self._settings.progression_min_image_quality_score
        ):
            return False
        return not _BLOCKING_QUALITY_FLAGS.intersection(image.quality_flags)

    async def _load_images(
        self, farmer_id: UUID, images: list[DiagnosisImage]
    ) -> tuple[ProgressionImage, ...]:
        payload: list[ProgressionImage] = []
        for image in images:
            try:
                content = await self._storage.read_private(
                    owner_id=farmer_id,
                    key=image.object_key,
                )
            except (OSError, ValueError) as exc:
                raise ApplicationError(
                    code="PROGRESSION_IMAGE_UNAVAILABLE", status_code=503
                ) from exc
            if len(content) != image.size_bytes or len(content) > self._settings.max_image_bytes:
                raise ApplicationError(code="PROGRESSION_IMAGE_INVALID", status_code=422)
            payload.append(
                ProgressionImage(
                    image_id=image.id,
                    content=content,
                    captured_at=image.captured_or_uploaded_at,
                )
            )
        return tuple(payload)
