"""Multi-image diagnosis lifecycle and ownership rules."""

import math
from datetime import UTC, datetime
from uuid import UUID, uuid4

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.inference.provider import CaseInference, LeafInferenceProvider, Prediction
from app.integrations.storage.provider import ObjectStorageProvider, StoredObject
from app.modules.diagnoses.context import DiagnosisContextCleaner
from app.modules.diagnoses.images import ImagePreprocessor, PreparedImage
from app.modules.diagnoses.models import (
    DiagnosisAssessment,
    DiagnosisCase,
    DiagnosisFeedback,
    DiagnosisImage,
    DiagnosisPrediction,
)
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.diagnoses.schemas import (
    AssessmentHistoryResponse,
    AssessmentResponse,
    ConfidenceLabel,
    DiagnosisCaseResponse,
    DiagnosisFeedbackResponse,
    DiagnosisFeedbackUpsert,
    DiagnosisImagePredictionResponse,
    DiagnosisImageResponse,
    DiagnosisLink,
    IncomingImage,
    PredictionResponse,
)
from app.modules.farms.repository import FarmRepository
from app.modules.reports.repository import ReportRepository
from app.modules.storage_cleanup.service import ObjectCleanupService


class DiagnosisService:
    """Coordinate image privacy, model inference, and case persistence."""

    def __init__(
        self,
        *,
        settings: Settings,
        repository: DiagnosisRepository,
        farm_repository: FarmRepository,
        report_repository: ReportRepository,
        cleanup: ObjectCleanupService,
        storage: ObjectStorageProvider,
        inference: LeafInferenceProvider,
        context_cleaner: DiagnosisContextCleaner,
    ) -> None:
        self._settings = settings
        self._repository = repository
        self._farms = farm_repository
        self._reports = report_repository
        self._cleanup = cleanup
        self._storage = storage
        self._inference = inference
        self._context_cleaner = context_cleaner
        self._preprocessor = ImagePreprocessor(settings)

    async def create_case(
        self,
        farmer_id: UUID,
        *,
        images: list[IncomingImage],
        plant_name: str | None,
        link: DiagnosisLink,
    ) -> DiagnosisCaseResponse:
        if not images:
            raise ApplicationError(code="SCAN_IMAGES_REQUIRED", status_code=422)
        if len(images) > self._settings.max_diagnosis_images:
            raise ApplicationError(code="SCAN_TOO_MANY_IMAGES", status_code=413)
        farm_id, plot_id, crop_id = await self._validated_link(farmer_id, link)
        case = DiagnosisCase(
            id=uuid4(),
            farmer_id=farmer_id,
            farm_id=farm_id,
            plot_id=plot_id,
            crop_id=crop_id,
            plant_name=plant_name,
            title=f"Leaf diagnosis - {datetime.now(tz=UTC).date().isoformat()}",
            status="processing",
        )
        return await self._process(
            farmer_id,
            case=case,
            incoming=images,
            is_new_case=True,
        )

    async def add_retakes(
        self,
        farmer_id: UUID,
        case_id: UUID,
        images: list[IncomingImage],
    ) -> DiagnosisCaseResponse:
        if not images:
            raise ApplicationError(code="SCAN_IMAGES_REQUIRED", status_code=422)
        if len(images) > self._settings.max_diagnosis_images:
            raise ApplicationError(code="SCAN_TOO_MANY_IMAGES", status_code=413)
        # Read without a row lock. Image preprocessing, private-object upload and
        # inference are external/CPU-heavy work and must not hold a DB lock.
        case = await self._case(farmer_id, case_id)
        if await self._repository.image_count(farmer_id, case_id) + len(images) > (
            self._settings.max_diagnosis_case_images
        ):
            raise ApplicationError(code="SCAN_CASE_IMAGE_LIMIT_REACHED", status_code=409)
        # End the read transaction before storage and inference. The case is
        # locked and the invariant rechecked immediately before persistence.
        await self._repository.commit()
        return await self._process(
            farmer_id,
            case=case,
            incoming=images,
            is_new_case=False,
        )

    async def list_cases(
        self,
        farmer_id: UUID,
        *,
        limit: int,
        offset: int,
        farm_id: UUID | None = None,
        plot_id: UUID | None = None,
        crop_id: UUID | None = None,
    ) -> list[DiagnosisCaseResponse]:
        if farm_id is not None and await self._farms.get_farm(farmer_id, farm_id) is None:
            raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
        if plot_id is not None and await self._farms.get_plot(farmer_id, plot_id) is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        if crop_id is not None and await self._farms.get_crop(farmer_id, crop_id) is None:
            raise ApplicationError(code="CROP_NOT_FOUND", status_code=404)
        cases = await self._repository.list_cases(
            farmer_id,
            limit=limit,
            offset=offset,
            farm_id=farm_id,
            plot_id=plot_id,
            crop_id=crop_id,
        )
        return [await self._response(farmer_id, case) for case in cases]

    async def get_case(self, farmer_id: UUID, case_id: UUID) -> DiagnosisCaseResponse:
        return await self._response(farmer_id, await self._case(farmer_id, case_id))

    async def image_page(
        self, farmer_id: UUID, case_id: UUID, *, limit: int, offset: int
    ) -> list[DiagnosisImageResponse]:
        await self._case(farmer_id, case_id)
        values = await self._repository.list_images(farmer_id, case_id, limit=limit, offset=offset)
        return [DiagnosisImageResponse.model_validate(item) for item in values]

    async def assessment_history(
        self, farmer_id: UUID, case_id: UUID, *, limit: int = 50, offset: int = 0
    ) -> list[AssessmentHistoryResponse]:
        await self._case(farmer_id, case_id)
        assessments = await self._repository.list_assessments(
            farmer_id, case_id, limit=limit, offset=offset
        )
        responses: list[AssessmentHistoryResponse] = []
        for assessment in reversed(assessments):
            predictions = await self._repository.assessment_predictions(assessment.id)
            combined = [item for item in predictions if item.scope == "combined"]
            responses.append(
                AssessmentHistoryResponse(
                    id=assessment.id,
                    predicted_crop=assessment.predicted_crop,
                    primary_disease=assessment.primary_disease,
                    confidence_label=ConfidenceLabel(assessment.confidence_label),
                    alternatives=[self._prediction_response(item) for item in combined[1:]],
                    image_ids=list(
                        dict.fromkeys(
                            item.image_id
                            for item in predictions
                            if item.scope == "image" and item.image_id is not None
                        )
                    ),
                    is_active=assessment.is_active,
                    model_name=assessment.model_name,
                    model_version=assessment.model_version,
                    created_at=assessment.created_at,
                )
            )
        return responses

    async def image_prediction_page(
        self, farmer_id: UUID, case_id: UUID, *, limit: int, offset: int
    ) -> list[DiagnosisImagePredictionResponse]:
        await self._case(farmer_id, case_id)
        values = await self._repository.image_predictions(
            farmer_id, case_id, limit=limit, offset=offset
        )
        grouped: dict[UUID, list[PredictionResponse]] = {}
        for item in values:
            if item.image_id is not None:
                grouped.setdefault(item.image_id, []).append(self._prediction_response(item))
        return [
            DiagnosisImagePredictionResponse(image_id=image_id, predictions=predictions)
            for image_id, predictions in grouped.items()
        ]

    async def read_image(self, farmer_id: UUID, case_id: UUID, image_id: UUID) -> bytes:
        await self._case(farmer_id, case_id)
        image = await self._repository.get_image(farmer_id, case_id, image_id)
        if image is None:
            raise ApplicationError(code="DIAGNOSIS_IMAGE_NOT_FOUND", status_code=404)
        return await self._storage.read_private(owner_id=farmer_id, key=image.object_key)

    async def link_case(
        self, farmer_id: UUID, case_id: UUID, link: DiagnosisLink
    ) -> DiagnosisCaseResponse:
        if not link.model_fields_set:
            raise ApplicationError(code="DIAGNOSIS_LINK_EMPTY", status_code=422)
        case = await self._case(farmer_id, case_id)
        farm_id, plot_id, crop_id = await self._validated_link(farmer_id, link)
        case.farm_id = farm_id
        case.plot_id = plot_id
        case.crop_id = crop_id
        await self._repository.commit()
        await self._repository.refresh(case)
        return await self._response(farmer_id, case)

    async def upsert_feedback(
        self,
        farmer_id: UUID,
        case_id: UUID,
        data: DiagnosisFeedbackUpsert,
    ) -> DiagnosisFeedbackResponse:
        await self._case(farmer_id, case_id)
        feedback = await self._repository.get_feedback(farmer_id, case_id)
        if feedback is None:
            feedback = DiagnosisFeedback(
                farmer_id=farmer_id,
                case_id=case_id,
                is_incorrect=data.is_incorrect,
            )
            self._repository.add(feedback)
        feedback.is_incorrect = data.is_incorrect
        feedback.corrected_crop = data.corrected_crop
        feedback.corrected_disease = data.corrected_disease
        feedback.notes = data.notes
        await self._repository.commit()
        await self._repository.refresh(feedback)
        return DiagnosisFeedbackResponse.model_validate(feedback)

    async def get_feedback(
        self, farmer_id: UUID, case_id: UUID
    ) -> DiagnosisFeedbackResponse | None:
        await self._case(farmer_id, case_id)
        feedback = await self._repository.get_feedback(farmer_id, case_id)
        return DiagnosisFeedbackResponse.model_validate(feedback) if feedback is not None else None

    async def delete_case(self, farmer_id: UUID, case_id: UUID) -> None:
        case = await self._case(farmer_id, case_id)
        await self._context_cleaner.delete_scan_context(farmer_id, case_id)
        images = await self._repository.list_images(farmer_id, case_id)
        report_images = await self._reports.list_images_for_case(farmer_id, case_id)
        jobs = [
            self._cleanup.enqueue(farmer_id, object_key, "diagnosis_case_deleted")
            for object_key in [
                *(image.object_key for image in images),
                *(image.object_key for image in report_images),
            ]
        ]
        await self._repository.delete_case(case)
        await self._repository.commit()
        await self._cleanup.process([job.id for job in jobs])

    async def _process(
        self,
        farmer_id: UUID,
        *,
        case: DiagnosisCase,
        incoming: list[IncomingImage],
        is_new_case: bool,
    ) -> DiagnosisCaseResponse:
        prepared = [await self._preprocessor.prepare(item.content) for item in incoming]
        stored: list[StoredObject] = []
        try:
            for image in prepared:
                stored.append(
                    await self._storage.put_private_image(
                        owner_id=farmer_id,
                        category="leaf-scans",
                        content=image.content,
                    )
                )
            inference = await self._inference.diagnose(
                farmer_id=farmer_id,
                images=tuple(image.content for image in prepared),
                plant_name=case.plant_name,
            )
            self._validate_inference(inference, len(prepared))
            new_models = self._new_image_models(
                farmer_id,
                case.id,
                incoming,
                prepared,
                stored,
            )
            self._apply_image_quality(new_models, inference)
            previous_image_predictions = await self._repository.case_image_predictions(
                farmer_id, case.id
            )
            combined_predictions = self._aggregate_case_predictions(
                previous=previous_image_predictions,
                current=inference,
            )
            assessment = await self._persist_result(
                farmer_id,
                case,
                new_models,
                inference,
                combined_predictions,
                is_new_case,
            )
        except Exception:
            await self._repository.rollback()
            jobs = [
                self._cleanup.enqueue(farmer_id, item.key, "diagnosis_create_rollback")
                for item in stored
            ]
            await self._repository.commit()
            await self._cleanup.process([job.id for job in jobs])
            raise

        await self._repository.refresh(case)
        if assessment.is_active:
            case.title = self._automatic_title(assessment)
            await self._repository.commit()
            await self._repository.refresh(case)
        return await self._response(farmer_id, case)

    async def _persist_result(
        self,
        farmer_id: UUID,
        case: DiagnosisCase,
        new_images: list[DiagnosisImage],
        inference: CaseInference,
        combined_predictions: list[Prediction],
        is_new_case: bool,
    ) -> DiagnosisAssessment:
        if not is_new_case:
            locked_case = await self._repository.get_case(farmer_id, case.id, for_update=True)
            if locked_case is None:
                raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
            case = locked_case
            if await self._repository.image_count(farmer_id, case.id) + len(new_images) > (
                self._settings.max_diagnosis_case_images
            ):
                raise ApplicationError(code="SCAN_CASE_IMAGE_LIMIT_REACHED", status_code=409)
        existing_assessment = await self._repository.get_active_assessment(farmer_id, case.id)
        primary = combined_predictions[0]
        should_activate = (
            existing_assessment is None or primary.confidence > existing_assessment.confidence
        )
        if should_activate:
            await self._repository.deactivate_assessments(farmer_id, case.id)
        if is_new_case:
            self._repository.add(case)
            # These models carry scalar UUID foreign keys rather than ORM
            # relationships, so PostgreSQL must see the parent row before the
            # dependent assessment and image rows are flushed.
            await self._repository.flush()
        for image in new_images:
            self._repository.add(image)
        assessment = DiagnosisAssessment(
            id=uuid4(),
            farmer_id=farmer_id,
            case_id=case.id,
            predicted_crop=primary.crop_name,
            primary_disease=primary.disease_name,
            confidence=primary.confidence,
            confidence_label=self._confidence_label(primary.confidence).value,
            model_name=inference.model_name,
            model_version=inference.model_version,
            is_active=should_activate,
        )
        self._repository.add(assessment)
        # Predictions reference both the assessment and (for per-image
        # evidence) the new image rows. Persist those parents first instead of
        # relying on unit-of-work relationship ordering that is not present.
        await self._repository.flush()
        for rank, prediction in enumerate(combined_predictions, start=1):
            self._repository.add(
                self._prediction_model(assessment.id, None, "combined", rank, prediction)
            )
        for image, image_result in zip(new_images, inference.images, strict=True):
            for rank, prediction in enumerate(image_result.predictions, start=1):
                self._repository.add(
                    self._prediction_model(
                        assessment.id,
                        image.id,
                        "image",
                        rank,
                        prediction,
                    )
                )
        case.status = "completed"
        await self._repository.commit()
        return assessment

    @staticmethod
    def _aggregate_case_predictions(
        *,
        previous: list[DiagnosisPrediction],
        current: CaseInference,
    ) -> list[Prediction]:
        """Average ranked evidence across every immutable image in the case."""

        totals: dict[tuple[str, str], float] = {}
        previous_image_ids = {item.image_id for item in previous if item.image_id is not None}
        image_count = len(previous_image_ids) + len(current.images)
        for stored_item in previous:
            key = (stored_item.crop_name, stored_item.disease_name)
            totals[key] = totals.get(key, 0.0) + stored_item.confidence
        for image_result in current.images:
            for current_item in image_result.predictions:
                key = (current_item.crop_name, current_item.disease_name)
                totals[key] = totals.get(key, 0.0) + current_item.confidence
        ranked = sorted(totals.items(), key=lambda item: item[1], reverse=True)
        return [
            Prediction(crop_name, disease_name, total / image_count)
            for (crop_name, disease_name), total in ranked[:5]
        ]

    def _new_image_models(
        self,
        farmer_id: UUID,
        case_id: UUID,
        incoming: list[IncomingImage],
        prepared: list[PreparedImage],
        stored: list[StoredObject],
    ) -> list[DiagnosisImage]:
        return [
            DiagnosisImage(
                id=uuid4(),
                farmer_id=farmer_id,
                case_id=case_id,
                object_key=stored_item.key,
                size_bytes=stored_item.size_bytes,
                width=prepared_item.width,
                height=prepared_item.height,
                captured_or_uploaded_at=incoming_item.captured_or_uploaded_at,
                quality_flags=[],
            )
            for incoming_item, prepared_item, stored_item in zip(
                incoming, prepared, stored, strict=True
            )
        ]

    @staticmethod
    def _apply_image_quality(images: list[DiagnosisImage], inference: CaseInference) -> None:
        for image, result in zip(images, inference.images, strict=True):
            image.quality_score = result.quality_score
            image.quality_flags = list(result.quality_flags)

    @staticmethod
    def _prediction_model(
        assessment_id: UUID,
        image_id: UUID | None,
        scope: str,
        rank: int,
        prediction: Prediction,
    ) -> DiagnosisPrediction:
        return DiagnosisPrediction(
            assessment_id=assessment_id,
            image_id=image_id,
            scope=scope,
            rank=rank,
            crop_name=prediction.crop_name,
            disease_name=prediction.disease_name,
            confidence=prediction.confidence,
        )

    @staticmethod
    def _prediction_response(value: DiagnosisPrediction) -> PredictionResponse:
        return PredictionResponse(
            crop_name=value.crop_name,
            disease_name=value.disease_name,
            rank=value.rank,
        )

    async def _response(self, farmer_id: UUID, case: DiagnosisCase) -> DiagnosisCaseResponse:
        image_count = await self._repository.image_count(farmer_id, case.id)
        images = await self._repository.recent_images(farmer_id, case.id, limit=20)
        assessment = await self._repository.get_active_assessment(farmer_id, case.id)
        assessment_response: AssessmentResponse | None = None
        if assessment is not None:
            predictions = await self._repository.combined_predictions(assessment.id)
            assessment_response = AssessmentResponse(
                id=assessment.id,
                predicted_crop=assessment.predicted_crop,
                primary_disease=assessment.primary_disease,
                confidence_label=ConfidenceLabel(assessment.confidence_label),
                alternatives=[
                    PredictionResponse(
                        crop_name=item.crop_name,
                        disease_name=item.disease_name,
                        rank=item.rank,
                    )
                    for item in predictions[1:]
                ],
                is_active=assessment.is_active,
                model_name=assessment.model_name,
                model_version=assessment.model_version,
                created_at=assessment.created_at,
            )
        retake = bool(
            assessment_response
            and (
                assessment_response.confidence_label is ConfidenceLabel.LOW
                or any(image.quality_flags for image in images)
            )
        )
        return DiagnosisCaseResponse(
            id=case.id,
            title=case.title,
            status=case.status,
            plant_name=case.plant_name,
            farm_id=case.farm_id,
            plot_id=case.plot_id,
            crop_id=case.crop_id,
            image_count=image_count,
            images=[DiagnosisImageResponse.model_validate(item) for item in images],
            active_assessment=assessment_response,
            retake_recommended=retake,
            created_at=case.created_at,
            updated_at=case.updated_at,
        )

    async def _validated_link(
        self, farmer_id: UUID, link: DiagnosisLink
    ) -> tuple[UUID | None, UUID | None, UUID | None]:
        farm_id, plot_id, crop_id = link.farm_id, link.plot_id, link.crop_id
        if crop_id is not None and plot_id is None:
            raise ApplicationError(code="DIAGNOSIS_CROP_REQUIRES_PLOT", status_code=422)
        if plot_id is not None:
            plot = await self._farms.get_plot(farmer_id, plot_id)
            if plot is None:
                raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
            if farm_id is not None and plot.farm_id != farm_id:
                raise ApplicationError(code="PLOT_NOT_IN_FARM", status_code=409)
            farm_id = plot.farm_id
        elif farm_id is not None and await self._farms.get_farm(farmer_id, farm_id) is None:
            raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
        if crop_id is not None:
            crop = await self._farms.get_crop(farmer_id, crop_id)
            if crop is None:
                raise ApplicationError(code="CROP_NOT_FOUND", status_code=404)
            if crop.plot_id != plot_id:
                raise ApplicationError(code="CROP_NOT_IN_PLOT", status_code=409)
        return farm_id, plot_id, crop_id

    async def _case(
        self, farmer_id: UUID, case_id: UUID, *, for_update: bool = False
    ) -> DiagnosisCase:
        case = await self._repository.get_case(farmer_id, case_id, for_update=for_update)
        if case is None:
            raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
        return case

    def _confidence_label(self, confidence: float) -> ConfidenceLabel:
        if confidence < self._settings.diagnosis_low_confidence_threshold:
            return ConfidenceLabel.LOW
        if confidence < self._settings.diagnosis_high_confidence_threshold:
            return ConfidenceLabel.MEDIUM
        return ConfidenceLabel.HIGH

    @staticmethod
    def _validate_inference(result: CaseInference, expected_images: int) -> None:
        if (
            len(result.images) != expected_images
            or not result.combined_predictions
            or len(result.combined_predictions) > 5
        ):
            raise ApplicationError(code="LEAF_MODEL_INVALID_RESPONSE", status_code=502)
        all_prediction_sets = [
            result.combined_predictions,
            *(item.predictions for item in result.images),
        ]
        if any(not predictions or len(predictions) > 5 for predictions in all_prediction_sets):
            raise ApplicationError(code="LEAF_MODEL_INVALID_RESPONSE", status_code=502)
        for predictions in all_prediction_sets:
            for prediction in predictions:
                if (
                    not prediction.crop_name.strip()
                    or not prediction.disease_name.strip()
                    or not math.isfinite(prediction.confidence)
                    or not 0 <= prediction.confidence <= 1
                ):
                    raise ApplicationError(code="LEAF_MODEL_INVALID_RESPONSE", status_code=502)
        if any(
            not math.isfinite(item.quality_score) or not 0 <= item.quality_score <= 1
            for item in result.images
        ):
            raise ApplicationError(code="LEAF_MODEL_INVALID_RESPONSE", status_code=502)

    @staticmethod
    def _automatic_title(assessment: DiagnosisAssessment) -> str:
        created = assessment.created_at or datetime.now(tz=UTC)
        return (
            f"{assessment.predicted_crop} - {assessment.primary_disease} - "
            f"{created.date().isoformat()}"
        )
