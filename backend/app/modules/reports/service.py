"""Immutable farmer-approved diagnosis report sharing."""

import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from app.core.errors import ApplicationError
from app.integrations.storage.provider import ObjectStorageProvider
from app.modules.diagnoses.repository import DiagnosisRepository
from app.modules.farms.repository import FarmRepository
from app.modules.reports.models import DiagnosisReport, DiagnosisReportImage
from app.modules.reports.repository import ReportRepository
from app.modules.reports.schemas import (
    CreatedReportResponse,
    DiagnosisReportResponse,
    PublicDiagnosisReport,
    ReportApproval,
    ReportImageResponse,
)
from app.modules.storage_cleanup.service import ObjectCleanupService


class ReportService:
    _MAX_EXPIRY = timedelta(days=30)

    def __init__(
        self,
        *,
        repository: ReportRepository,
        diagnoses: DiagnosisRepository,
        farms: FarmRepository,
        storage: ObjectStorageProvider,
        cleanup: ObjectCleanupService,
    ) -> None:
        self._repository = repository
        self._diagnoses = diagnoses
        self._farms = farms
        self._storage = storage
        self._cleanup = cleanup

    async def create(
        self, farmer_id: UUID, case_id: UUID, approval: ReportApproval
    ) -> CreatedReportResponse:
        now = datetime.now(tz=UTC)
        if approval.expires_at <= now or approval.expires_at > now + self._MAX_EXPIRY:
            raise ApplicationError(code="REPORT_EXPIRY_INVALID", status_code=422)
        case = await self._diagnoses.get_case(farmer_id, case_id)
        if case is None:
            raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
        assessment = await self._diagnoses.get_active_assessment(farmer_id, case_id)
        if assessment is None:
            raise ApplicationError(code="DIAGNOSIS_RESULT_NOT_AVAILABLE", status_code=409)
        source_images = await self._diagnoses.list_images(farmer_id, case_id)
        by_id = {image.id: image for image in source_images}
        if len(set(approval.image_ids)) != len(approval.image_ids):
            raise ApplicationError(code="REPORT_IMAGE_SELECTION_INVALID", status_code=422)
        try:
            selected = [by_id[image_id] for image_id in approval.image_ids]
        except KeyError as exc:
            raise ApplicationError(code="REPORT_IMAGE_NOT_IN_CASE", status_code=409) from exc

        snapshot: dict[str, object] = {
            "diagnosis": {
                "predicted_crop": assessment.predicted_crop,
                "primary_disease": assessment.primary_disease,
                "confidence_label": assessment.confidence_label,
                "assessed_at": assessment.created_at.isoformat(),
            }
        }
        approved_fields = ["diagnosis"]
        if approval.include_alternatives:
            predictions = await self._diagnoses.combined_predictions(assessment.id)
            snapshot["alternatives"] = [
                {"crop_name": item.crop_name, "disease_name": item.disease_name}
                for item in predictions[1:]
            ]
            approved_fields.append("alternatives")
        if approval.include_feedback:
            feedback = await self._diagnoses.get_feedback(farmer_id, case_id)
            if feedback is not None:
                snapshot["farmer_feedback"] = {
                    "is_incorrect": feedback.is_incorrect,
                    "corrected_crop": feedback.corrected_crop,
                    "corrected_disease": feedback.corrected_disease,
                    "notes": feedback.notes,
                }
                approved_fields.append("farmer_feedback")
        if approval.include_plot_name or approval.include_plot_location:
            if case.plot_id is None:
                raise ApplicationError(code="REPORT_CASE_HAS_NO_PLOT", status_code=409)
            plot = await self._farms.get_plot(farmer_id, case.plot_id)
            if plot is None:
                raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
            plot_snapshot: dict[str, object] = {}
            if approval.include_plot_name:
                plot_snapshot["name"] = plot.name
                approved_fields.append("plot_name")
            if approval.include_plot_location:
                plot_snapshot["location_label"] = plot.location_label
                plot_snapshot["latitude"] = str(plot.latitude)
                plot_snapshot["longitude"] = str(plot.longitude)
                approved_fields.append("plot_location")
            snapshot["plot"] = plot_snapshot
        if selected:
            approved_fields.append("images")

        token = secrets.token_urlsafe(32)
        report = DiagnosisReport(
            id=uuid4(),
            farmer_id=farmer_id,
            diagnosis_case_id=case_id,
            title=approval.title or case.title,
            snapshot=snapshot,
            approved_fields=approved_fields,
            token_hash=self._hash(token),
            expires_at=approval.expires_at,
            status="active",
        )
        self._repository.add(report)
        copied_keys: list[str] = []
        try:
            for source in selected:
                content = await self._storage.read_private(
                    owner_id=farmer_id, key=source.object_key
                )
                stored = await self._storage.put_private_image(
                    owner_id=farmer_id,
                    category="diagnosis-reports",
                    content=content,
                )
                copied_keys.append(stored.key)
                self._repository.add(
                    DiagnosisReportImage(
                        farmer_id=farmer_id,
                        report_id=report.id,
                        source_image_id=source.id,
                        object_key=stored.key,
                        size_bytes=stored.size_bytes,
                    )
                )
            await self._repository.commit()
        except Exception:
            await self._repository.rollback()
            jobs = [
                self._cleanup.enqueue(farmer_id, key, "report_create_rollback")
                for key in copied_keys
            ]
            await self._repository.commit()
            await self._cleanup.process([job.id for job in jobs])
            raise
        await self._repository.refresh(report)
        return CreatedReportResponse(
            **(await self._response(report)).model_dump(), share_token=token
        )

    async def list_for_case(self, farmer_id: UUID, case_id: UUID) -> list[DiagnosisReportResponse]:
        if await self._diagnoses.get_case(farmer_id, case_id) is None:
            raise ApplicationError(code="DIAGNOSIS_CASE_NOT_FOUND", status_code=404)
        return [
            await self._response(report)
            for report in await self._repository.list_for_case(farmer_id, case_id)
        ]

    async def revoke(self, farmer_id: UUID, report_id: UUID) -> DiagnosisReportResponse:
        report = await self._repository.get(farmer_id, report_id)
        if report is None:
            raise ApplicationError(code="REPORT_NOT_FOUND", status_code=404)
        if report.status != "revoked":
            report.status = "revoked"
            report.revoked_at = datetime.now(tz=UTC)
            await self._repository.commit()
            await self._repository.refresh(report)
        return await self._response(report)

    async def public(self, report_id: UUID, token: str) -> PublicDiagnosisReport:
        report = await self._public_report(report_id, token)
        images = await self._repository.list_images(report.id)
        return PublicDiagnosisReport(
            id=report.id,
            title=report.title,
            snapshot=report.snapshot,
            approved_fields=report.approved_fields,
            expires_at=report.expires_at,
            created_at=report.created_at,
            images=[ReportImageResponse.model_validate(image) for image in images],
        )

    async def owner_image(self, farmer_id: UUID, report_id: UUID, image_id: UUID) -> bytes:
        report = await self._repository.get(farmer_id, report_id)
        if report is None:
            raise ApplicationError(code="REPORT_NOT_FOUND", status_code=404)
        image = await self._repository.get_image(report.id, image_id)
        if image is None:
            raise ApplicationError(code="REPORT_IMAGE_NOT_FOUND", status_code=404)
        return await self._storage.read_private(owner_id=farmer_id, key=image.object_key)

    async def public_image(self, report_id: UUID, token: str, image_id: UUID) -> bytes:
        report = await self._public_report(report_id, token)
        image = await self._repository.get_image(report.id, image_id)
        if image is None:
            raise ApplicationError(code="REPORT_IMAGE_NOT_FOUND", status_code=404)
        return await self._storage.read_private(owner_id=report.farmer_id, key=image.object_key)

    async def _public_report(self, report_id: UUID, token: str) -> DiagnosisReport:
        if len(token) < 32:
            raise ApplicationError(code="REPORT_NOT_FOUND", status_code=404)
        report = await self._repository.get_by_token_hash(self._hash(token))
        now = datetime.now(tz=UTC)
        if (
            report is None
            or not secrets.compare_digest(str(report.id), str(report_id))
            or report.status != "active"
            or self._aware(report.expires_at) <= now
        ):
            raise ApplicationError(code="REPORT_NOT_FOUND", status_code=404)
        return report

    async def _response(self, report: DiagnosisReport) -> DiagnosisReportResponse:
        images = await self._repository.list_images(report.id)
        return DiagnosisReportResponse(
            id=report.id,
            diagnosis_case_id=report.diagnosis_case_id,
            title=report.title,
            snapshot=report.snapshot,
            approved_fields=report.approved_fields,
            status=report.status,
            expires_at=report.expires_at,
            created_at=report.created_at,
            revoked_at=report.revoked_at,
            images=[ReportImageResponse.model_validate(image) for image in images],
        )

    @staticmethod
    def _hash(token: str) -> str:
        return hashlib.sha256(token.encode()).hexdigest()

    @staticmethod
    def _aware(value: datetime) -> datetime:
        return value if value.tzinfo is not None else value.replace(tzinfo=UTC)
