"""Owner-scoped and token-scoped report persistence."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.reports.models import DiagnosisReport, DiagnosisReportImage


class ReportRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get(
        self, farmer_id: UUID, report_id: UUID, *, for_update: bool = False
    ) -> DiagnosisReport | None:
        statement = select(DiagnosisReport).where(
                DiagnosisReport.id == report_id,
                DiagnosisReport.farmer_id == farmer_id,
            )
        if for_update:
            statement = statement.with_for_update()
        result = await self.session.execute(statement)
        return result.scalar_one_or_none()

    async def get_by_token_hash(self, token_hash: str) -> DiagnosisReport | None:
        result = await self.session.execute(
            select(DiagnosisReport).where(DiagnosisReport.token_hash == token_hash)
        )
        return result.scalar_one_or_none()

    async def list_for_case(self, farmer_id: UUID, case_id: UUID) -> list[DiagnosisReport]:
        result = await self.session.scalars(
            select(DiagnosisReport)
            .where(
                DiagnosisReport.farmer_id == farmer_id,
                DiagnosisReport.diagnosis_case_id == case_id,
            )
            .order_by(DiagnosisReport.created_at.desc())
        )
        return list(result)

    async def list_images(self, report_id: UUID) -> list[DiagnosisReportImage]:
        result = await self.session.scalars(
            select(DiagnosisReportImage)
            .where(DiagnosisReportImage.report_id == report_id)
            .order_by(DiagnosisReportImage.created_at)
        )
        return list(result)

    async def get_image(self, report_id: UUID, image_id: UUID) -> DiagnosisReportImage | None:
        result = await self.session.execute(
            select(DiagnosisReportImage).where(
                DiagnosisReportImage.id == image_id,
                DiagnosisReportImage.report_id == report_id,
            )
        )
        return result.scalar_one_or_none()

    async def list_images_for_case(
        self, farmer_id: UUID, case_id: UUID
    ) -> list[DiagnosisReportImage]:
        result = await self.session.scalars(
            select(DiagnosisReportImage)
            .join(DiagnosisReport, DiagnosisReport.id == DiagnosisReportImage.report_id)
            .where(
                DiagnosisReport.farmer_id == farmer_id,
                DiagnosisReport.diagnosis_case_id == case_id,
            )
        )
        return list(result)

    def add(self, value: DiagnosisReport | DiagnosisReportImage) -> None:
        self.session.add(value)

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()

    async def refresh(self, value: DiagnosisReport | DiagnosisReportImage) -> None:
        await self.session.refresh(value)

    async def delete_image(self, value: DiagnosisReportImage) -> None:
        await self.session.delete(value)
