"""Owner-scoped persistence for diagnosis cases."""

from uuid import UUID

from sqlalchemy import select, update
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

    async def list_cases(self, farmer_id: UUID, *, limit: int, offset: int) -> list[DiagnosisCase]:
        result = await self.session.scalars(
            select(DiagnosisCase)
            .where(DiagnosisCase.farmer_id == farmer_id)
            .order_by(DiagnosisCase.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(result)

    async def list_images(self, farmer_id: UUID, case_id: UUID) -> list[DiagnosisImage]:
        result = await self.session.scalars(
            select(DiagnosisImage)
            .where(
                DiagnosisImage.farmer_id == farmer_id,
                DiagnosisImage.case_id == case_id,
            )
            .order_by(DiagnosisImage.captured_or_uploaded_at, DiagnosisImage.created_at)
        )
        return list(result)

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
        self, farmer_id: UUID, case_id: UUID, *, limit: int = 5
    ) -> list[DiagnosisAssessment]:
        result = await self.session.scalars(
            select(DiagnosisAssessment)
            .where(
                DiagnosisAssessment.farmer_id == farmer_id,
                DiagnosisAssessment.case_id == case_id,
            )
            .order_by(DiagnosisAssessment.created_at.desc())
            .limit(limit)
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
