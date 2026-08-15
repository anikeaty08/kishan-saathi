"""Automatic privacy retention for expired public diagnosis reports."""

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.reports.models import DiagnosisReport, DiagnosisReportImage
from app.modules.storage_cleanup.service import ObjectCleanupService


class ReportRetentionService:
    """Revoke expired shares and durably remove their copied images."""

    def __init__(self, session: AsyncSession, cleanup: ObjectCleanupService) -> None:
        self._session = session
        self._cleanup = cleanup

    async def expire_due(self, *, limit: int) -> int:
        now = datetime.now(tz=UTC)
        reports = list(
            await self._session.scalars(
                select(DiagnosisReport)
                .where(
                    DiagnosisReport.status == "active",
                    DiagnosisReport.expires_at <= now,
                )
                .order_by(DiagnosisReport.expires_at, DiagnosisReport.id)
                .limit(limit)
                .with_for_update(skip_locked=True)
            )
        )
        if not reports:
            await self._session.rollback()
            return 0
        report_ids = [report.id for report in reports]
        images = list(
            await self._session.scalars(
                select(DiagnosisReportImage).where(
                    DiagnosisReportImage.report_id.in_(report_ids)
                )
            )
        )
        jobs = [
            self._cleanup.enqueue(image.farmer_id, image.object_key, "report_expired")
            for image in images
        ]
        for image in images:
            await self._session.delete(image)
        for report in reports:
            report.status = "revoked"
            report.revoked_at = now
        await self._session.commit()
        await self._cleanup.process([job.id for job in jobs])
        return len(reports)
