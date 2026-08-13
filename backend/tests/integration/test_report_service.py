"""Farmer-approved report snapshot and revocation coverage."""

from datetime import UTC, datetime, timedelta
from io import BytesIO
from pathlib import Path
from uuid import UUID

import pytest
from PIL import Image
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.errors import ApplicationError
from app.database.base import Base
from app.integrations.storage.local import LocalObjectStorage
from app.modules.diagnoses.models import DiagnosisAssessment, DiagnosisCase, DiagnosisImage
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.models import Plot
from app.modules.farms.repository import FarmRepository
from app.modules.reports.repository import ReportRepository
from app.modules.reports.schemas import ReportApproval
from app.modules.reports.service import ReportService
from app.modules.storage_cleanup.service import ObjectCleanupService
from app.modules.users.models import FarmerProfile

FARMER = UUID("00000000-0000-0000-0000-000000000091")


@pytest.mark.asyncio
async def test_report_is_approved_snapshot_and_revocable(tmp_path: Path) -> None:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    storage = LocalObjectStorage(tmp_path)

    try:
        async with sessions() as session:
            session.add(
                FarmerProfile(
                    id=FARMER,
                    cognito_sub="reports",
                    cognito_username="reports@example.com",
                    email="reports@example.com",
                )
            )
            plot = Plot(
                farmer_id=FARMER,
                name="North Plot",
                latitude=18,
                longitude=74,
                location_label="Village A",
            )
            session.add(plot)
            await session.flush()
            case = DiagnosisCase(
                farmer_id=FARMER,
                plot_id=plot.id,
                title="Tomato diagnosis",
                status="completed",
            )
            session.add(case)
            await session.flush()
            stored = await storage.put_private_image(
                owner_id=FARMER, category="leaf-scans", content=_image()
            )
            image = DiagnosisImage(
                farmer_id=FARMER,
                case_id=case.id,
                object_key=stored.key,
                size_bytes=stored.size_bytes,
                width=200,
                height=200,
                captured_or_uploaded_at=datetime.now(tz=UTC),
                quality_flags=[],
            )
            session.add(image)
            session.add(
                DiagnosisAssessment(
                    farmer_id=FARMER,
                    case_id=case.id,
                    predicted_crop="Tomato",
                    primary_disease="Early blight",
                    confidence=0.83,
                    confidence_label="high",
                    model_name="ensemble",
                    model_version="1",
                    is_active=True,
                )
            )
            await session.commit()
            service = ReportService(
                repository=ReportRepository(session),
                diagnoses=DiagnosisRepository(session),
                farms=FarmRepository(session),
                storage=storage,
                cleanup=ObjectCleanupService(session, storage),
            )

            created = await service.create(
                FARMER,
                case.id,
                ReportApproval(
                    include_plot_name=True,
                    include_plot_location=False,
                    image_ids=[image.id],
                    expires_at=datetime.now(tz=UTC) + timedelta(days=2),
                ),
            )
            public = await service.public(created.id, created.share_token)
            public_image = await service.public_image(
                created.id, created.share_token, public.images[0].id
            )
            await service.revoke(FARMER, created.id)
            with pytest.raises(ApplicationError) as revoked:
                await service.public(created.id, created.share_token)
    finally:
        await engine.dispose()

    assert "plot_name" in public.approved_fields
    assert "plot_location" not in public.approved_fields
    assert "latitude" not in str(public.snapshot)
    assert public_image == _image()
    assert revoked.value.code == "REPORT_NOT_FOUND"


def _image() -> bytes:
    value = BytesIO()
    Image.new("RGB", (200, 200), color=(30, 130, 40)).save(value, format="JPEG")
    return value.getvalue()
