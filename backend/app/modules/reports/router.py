"""Authenticated approval endpoints and token-scoped expert access."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Response, status

from app.modules.reports.dependencies import get_report_service
from app.modules.reports.schemas import (
    CreatedReportResponse,
    DiagnosisReportResponse,
    PublicDiagnosisReport,
    ReportApproval,
)
from app.modules.reports.service import ReportService
from app.modules.users.dependencies import get_current_farmer_id

router = APIRouter(tags=["diagnosis-reports"])
FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[ReportService, Depends(get_report_service)]


@router.post(
    "/diagnoses/{case_id}/reports",
    response_model=CreatedReportResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_report(
    case_id: UUID, data: ReportApproval, farmer_id: FarmerId, service: Service
) -> CreatedReportResponse:
    return await service.create(farmer_id, case_id, data)


@router.get("/diagnoses/{case_id}/reports", response_model=list[DiagnosisReportResponse])
async def list_reports(
    case_id: UUID, farmer_id: FarmerId, service: Service
) -> list[DiagnosisReportResponse]:
    return await service.list_for_case(farmer_id, case_id)


@router.post("/diagnosis-reports/{report_id}/revoke", response_model=DiagnosisReportResponse)
async def revoke_report(
    report_id: UUID, farmer_id: FarmerId, service: Service
) -> DiagnosisReportResponse:
    return await service.revoke(farmer_id, report_id)


@router.get("/diagnosis-reports/{report_id}/images/{image_id}")
async def owner_report_image(
    report_id: UUID,
    image_id: UUID,
    farmer_id: FarmerId,
    service: Service,
) -> Response:
    return Response(
        content=await service.owner_image(farmer_id, report_id, image_id),
        media_type="image/jpeg",
        headers={"Cache-Control": "private, no-store"},
    )


ShareToken = Annotated[str, Header(alias="X-Report-Token", min_length=32, max_length=128)]


@router.get("/shared/diagnosis-reports/{report_id}", response_model=PublicDiagnosisReport)
async def public_report(
    report_id: UUID, token: ShareToken, service: Service, response: Response
) -> PublicDiagnosisReport:
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Pragma"] = "no-cache"
    return await service.public(report_id, token)


@router.get("/shared/diagnosis-reports/{report_id}/images/{image_id}")
async def public_report_image(
    report_id: UUID, image_id: UUID, token: ShareToken, service: Service
) -> Response:
    return Response(
        content=await service.public_image(report_id, token, image_id),
        media_type="image/jpeg",
        headers={"Cache-Control": "private, no-store", "X-Robots-Tag": "noindex"},
    )
