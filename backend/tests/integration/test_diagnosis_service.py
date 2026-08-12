"""Integration tests for multi-image diagnosis lifecycle."""

from datetime import UTC, datetime, timedelta
from io import BytesIO
from pathlib import Path
from uuid import UUID

import pytest
from PIL import Image
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.database.base import Base
from app.integrations.inference.provider import (
    CaseInference,
    ImageInference,
    LeafInferenceProvider,
    Prediction,
)
from app.integrations.storage.local import LocalObjectStorage
from app.modules.diagnoses.models import DiagnosisAssessment, DiagnosisCase
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.diagnoses.schemas import (
    DiagnosisFeedbackUpsert,
    DiagnosisLink,
    IncomingImage,
)
from app.modules.diagnoses.service import DiagnosisService
from app.modules.farms.repository import FarmRepository
from app.modules.reports.repository import ReportRepository
from app.modules.storage_cleanup.service import ObjectCleanupService
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-000000000001")
OTHER = UUID("00000000-0000-0000-0000-000000000002")


class SequencedInference(LeafInferenceProvider):
    """Return deterministic assessments for initial and retake calls."""

    def __init__(self, confidences: list[float]) -> None:
        self.confidences = iter(confidences)
        self.plant_names: list[str | None] = []

    async def diagnose(
        self, *, images: tuple[bytes, ...], plant_name: str | None
    ) -> CaseInference:
        confidence = next(self.confidences)
        self.plant_names.append(plant_name)
        per_image = tuple(
            ImageInference(
                predictions=(Prediction("Tomato", "Early blight", confidence),),
                quality_score=0.9,
            )
            for _ in images
        )
        return CaseInference(
            combined_predictions=(
                Prediction("Tomato", "Early blight", confidence),
                Prediction("Tomato", "Late blight", max(confidence - 0.2, 0)),
            ),
            images=per_image,
            model_name="test-ensemble",
            model_version="1",
        )

    async def close(self) -> None:
        return None


class FailingInference(LeafInferenceProvider):
    async def diagnose(
        self, *, images: tuple[bytes, ...], plant_name: str | None
    ) -> CaseInference:
        del images, plant_name
        raise ApplicationError(code="LEAF_MODEL_UNAVAILABLE", status_code=503)

    async def close(self) -> None:
        return None


@pytest.mark.asyncio
async def test_case_retakes_feedback_owner_isolation_and_deletion(tmp_path: Path) -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    storage = LocalObjectStorage(tmp_path)
    inference = SequencedInference([0.45, 0.82, 0.60])
    settings = Settings(_env_file=None)

    try:
        async with sessions() as session:
            session.add_all([_farmer(FARMER, "a"), _farmer(OTHER, "b")])
            await session.commit()
            service = DiagnosisService(
                settings=settings,
                repository=DiagnosisRepository(session),
                farm_repository=FarmRepository(session),
                report_repository=ReportRepository(session),
                cleanup=ObjectCleanupService(session, storage),
                storage=storage,
                inference=inference,
            )
            initial = await service.create_case(
                FARMER,
                images=[_incoming(0), _incoming(1)],
                plant_name="Tomato",
                link=DiagnosisLink(),
            )
            stronger = await service.add_retakes(FARMER, initial.id, [_incoming(2)])
            weaker = await service.add_retakes(FARMER, initial.id, [_incoming(3)])
            feedback = await service.upsert_feedback(
                FARMER,
                initial.id,
                DiagnosisFeedbackUpsert(
                    is_incorrect=True,
                    corrected_disease="Septoria leaf spot",
                ),
            )
            with pytest.raises(ApplicationError) as hidden:
                await service.get_case(OTHER, initial.id)

            assessments = await session.scalars(
                select(DiagnosisAssessment)
                .where(DiagnosisAssessment.case_id == initial.id)
                .order_by(DiagnosisAssessment.created_at)
            )
            assessment_rows = list(assessments)
            image_paths = list(tmp_path.rglob("*.jpg"))
            await service.delete_case(FARMER, initial.id)
            remaining = await session.scalar(
                select(func.count()).select_from(DiagnosisCase)
            )
    finally:
        await engine.dispose()

    assert initial.active_assessment is not None
    assert initial.active_assessment.confidence_label == "low"
    assert initial.retake_recommended is True
    assert len(initial.images) == 2
    assert stronger.active_assessment is not None
    assert stronger.active_assessment.confidence_label == "high"
    assert len(stronger.images) == 3
    assert weaker.active_assessment is not None
    assert weaker.active_assessment.id == stronger.active_assessment.id
    assert len(weaker.images) == 4
    assert [row.is_active for row in assessment_rows] == [False, True, False]
    assert feedback.corrected_disease == "Septoria leaf spot"
    assert hidden.value.code == "DIAGNOSIS_CASE_NOT_FOUND"
    assert inference.plant_names == ["Tomato", "Tomato", "Tomato"]
    assert len(image_paths) == 4
    assert not list(tmp_path.rglob("*.jpg"))
    assert remaining == 0


@pytest.mark.asyncio
async def test_failed_inference_removes_stored_objects_and_database_rows(tmp_path: Path) -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with sessions() as session:
            session.add(_farmer(FARMER, "a"))
            await session.commit()
            service = DiagnosisService(
                settings=Settings(_env_file=None),
                repository=DiagnosisRepository(session),
                farm_repository=FarmRepository(session),
                report_repository=ReportRepository(session),
                cleanup=ObjectCleanupService(session, LocalObjectStorage(tmp_path)),
                storage=LocalObjectStorage(tmp_path),
                inference=FailingInference(),
            )
            with pytest.raises(ApplicationError) as raised:
                await service.create_case(
                    FARMER,
                    images=[_incoming(0)],
                    plant_name=None,
                    link=DiagnosisLink(),
                )
            remaining = await session.scalar(
                select(func.count()).select_from(DiagnosisCase)
            )
    finally:
        await engine.dispose()

    assert raised.value.code == "LEAF_MODEL_UNAVAILABLE"
    assert not list(tmp_path.rglob("*.jpg"))
    assert remaining == 0


def _farmer(farmer_id: UUID, suffix: str) -> FarmerProfile:
    return FarmerProfile(
        id=farmer_id,
        cognito_sub=suffix,
        cognito_username=f"{suffix}@example.com",
        email=f"{suffix}@example.com",
    )


def _incoming(day_offset: int) -> IncomingImage:
    buffer = BytesIO()
    Image.new("RGB", (256, 256), color=(40 + day_offset, 120, 30)).save(
        buffer, format="PNG"
    )
    return IncomingImage(
        content=buffer.getvalue(),
        captured_or_uploaded_at=datetime.now(tz=UTC) + timedelta(days=day_offset),
    )
