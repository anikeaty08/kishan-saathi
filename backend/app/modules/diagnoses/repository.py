"""Owner-scoped persistence for diagnosis cases."""

from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.diagnoses.models import (
    DiagnosisAssessment,
    DiagnosisCase,
    DiagnosisFeedback,
    DiagnosisImage,
    DiagnosisPrediction,
)


class DiagnosisRepository:
    """Persist immutable model evidence and mutable case linkage."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_case(
        self, farmer_id: UUID, case_id: UUID, *, for_update: bool = False
    ) -> DiagnosisCase | None:
        statement = select(DiagnosisCase).where(
            DiagnosisCase.id == case_id,
            DiagnosisCase.farmer_id == farmer_id,
        )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement)
        return result.scalar_one_or_none()

    async def list_cases(
        self,
        farmer_id: UUID,
        *,
        limit: int,
        offset: int,
        farm_id: UUID | None = None,
        plot_id: UUID | None = None,
        crop_id: UUID | None = None,
    ) -> list[DiagnosisCase]:
        statement = select(DiagnosisCase).where(DiagnosisCase.farmer_id == farmer_id)
        if farm_id is not None:
            statement = statement.where(DiagnosisCase.farm_id == farm_id)
        if plot_id is not None:
            statement = statement.where(DiagnosisCase.plot_id == plot_id)
        if crop_id is not None:
            statement = statement.where(DiagnosisCase.crop_id == crop_id)
        result = await self.session.scalars(
            statement.order_by(DiagnosisCase.created_at.desc()).limit(limit).offset(offset)
        )
        return list(result)

    async def list_images(
        self,
        farmer_id: UUID,
        case_id: UUID,
        *,
        limit: int | None = None,
        offset: int = 0,
    ) -> list[DiagnosisImage]:
        statement = (
            select(DiagnosisImage)
            .where(
                DiagnosisImage.farmer_id == farmer_id,
                DiagnosisImage.case_id == case_id,
            )
            .order_by(DiagnosisImage.captured_or_uploaded_at, DiagnosisImage.created_at)
        )
        if limit is not None:
            statement = statement.limit(limit).offset(offset)
        result = await self.session.scalars(statement)
        return list(result)

    async def image_count(self, farmer_id: UUID, case_id: UUID) -> int:
        value = await self.session.scalar(
            select(func.count())
            .select_from(DiagnosisImage)
            .where(
                DiagnosisImage.farmer_id == farmer_id,
                DiagnosisImage.case_id == case_id,
            )
        )
        return int(value or 0)

    async def recent_images(
        self, farmer_id: UUID, case_id: UUID, *, limit: int
    ) -> list[DiagnosisImage]:
        result = await self.session.scalars(
            select(DiagnosisImage)
            .where(
                DiagnosisImage.farmer_id == farmer_id,
                DiagnosisImage.case_id == case_id,
            )
            .order_by(
                DiagnosisImage.captured_or_uploaded_at.desc(),
                DiagnosisImage.created_at.desc(),
            )
            .limit(limit)
        )
        return list(reversed(list(result)))

    async def get_image(
        self, farmer_id: UUID, case_id: UUID, image_id: UUID
    ) -> DiagnosisImage | None:
        result = await self.session.execute(
            select(DiagnosisImage).where(
                DiagnosisImage.id == image_id,
                DiagnosisImage.case_id == case_id,
                DiagnosisImage.farmer_id == farmer_id,
            )
        )
        return result.scalar_one_or_none()

    async def get_active_assessment(
        self, farmer_id: UUID, case_id: UUID
    ) -> DiagnosisAssessment | None:
        result = await self.session.execute(
            select(DiagnosisAssessment).where(
                DiagnosisAssessment.farmer_id == farmer_id,
                DiagnosisAssessment.case_id == case_id,
                DiagnosisAssessment.is_active.is_(True),
            )
        )
        return result.scalar_one_or_none()

    async def list_assessments(
        self, farmer_id: UUID, case_id: UUID, *, limit: int = 5, offset: int = 0
    ) -> list[DiagnosisAssessment]:
        result = await self.session.scalars(
            select(DiagnosisAssessment)
            .where(
                DiagnosisAssessment.farmer_id == farmer_id,
                DiagnosisAssessment.case_id == case_id,
            )
            .order_by(DiagnosisAssessment.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(result)

    async def combined_predictions(self, assessment_id: UUID) -> list[DiagnosisPrediction]:
        result = await self.session.scalars(
            select(DiagnosisPrediction)
            .where(
                DiagnosisPrediction.assessment_id == assessment_id,
                DiagnosisPrediction.scope == "combined",
            )
            .order_by(DiagnosisPrediction.rank)
        )
        return list(result)

    async def assessment_predictions(self, assessment_id: UUID) -> list[DiagnosisPrediction]:
        result = await self.session.scalars(
            select(DiagnosisPrediction)
            .where(DiagnosisPrediction.assessment_id == assessment_id)
            .order_by(
                DiagnosisPrediction.scope,
                DiagnosisPrediction.image_id,
                DiagnosisPrediction.rank,
            )
        )
        return list(result)

    async def image_predictions(
        self, farmer_id: UUID, case_id: UUID, *, limit: int, offset: int
    ) -> list[DiagnosisPrediction]:
        image_ids = (
            select(DiagnosisImage.id)
            .where(
                DiagnosisImage.farmer_id == farmer_id,
                DiagnosisImage.case_id == case_id,
            )
            .order_by(DiagnosisImage.captured_or_uploaded_at, DiagnosisImage.created_at)
            .limit(limit)
            .offset(offset)
        )
        result = await self.session.scalars(
            select(DiagnosisPrediction)
            .where(
                DiagnosisPrediction.scope == "image",
                DiagnosisPrediction.image_id.in_(image_ids),
            )
            .order_by(DiagnosisPrediction.image_id, DiagnosisPrediction.rank)
        )
        return list(result)

    async def case_image_predictions(
        self, farmer_id: UUID, case_id: UUID
    ) -> list[DiagnosisPrediction]:
        result = await self.session.scalars(
            select(DiagnosisPrediction)
            .join(
                DiagnosisAssessment,
                DiagnosisAssessment.id == DiagnosisPrediction.assessment_id,
            )
            .where(
                DiagnosisAssessment.farmer_id == farmer_id,
                DiagnosisAssessment.case_id == case_id,
                DiagnosisPrediction.scope == "image",
            )
            .order_by(DiagnosisPrediction.image_id, DiagnosisPrediction.rank)
        )
        return list(result)

    async def deactivate_assessments(self, farmer_id: UUID, case_id: UUID) -> None:
        await self.session.execute(
            update(DiagnosisAssessment)
            .where(
                DiagnosisAssessment.farmer_id == farmer_id,
                DiagnosisAssessment.case_id == case_id,
                DiagnosisAssessment.is_active.is_(True),
            )
            .values(is_active=False)
        )

    async def get_feedback(self, farmer_id: UUID, case_id: UUID) -> DiagnosisFeedback | None:
        result = await self.session.execute(
            select(DiagnosisFeedback).where(
                DiagnosisFeedback.farmer_id == farmer_id,
                DiagnosisFeedback.case_id == case_id,
            )
        )
        return result.scalar_one_or_none()

    def add(
        self,
        value: DiagnosisCase
        | DiagnosisImage
        | DiagnosisAssessment
        | DiagnosisPrediction
        | DiagnosisFeedback,
    ) -> None:
        self.session.add(value)

    async def flush(self) -> None:
        await self.session.flush()

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()

    async def refresh(self, value: DiagnosisCase | DiagnosisFeedback) -> None:
        await self.session.refresh(value)

    async def delete_case(self, value: DiagnosisCase) -> None:
        await self.session.delete(value)
