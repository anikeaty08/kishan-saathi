"""Authenticated multi-image leaf diagnosis API."""

from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Query, Response, UploadFile, status

from app.core.config import Settings
from app.core.dependencies import get_app_settings
from app.core.errors import ApplicationError
from app.modules.diagnoses.dependencies import get_diagnosis_service
from app.modules.diagnoses.schemas import (
    AssessmentHistoryResponse,
    DiagnosisCaseResponse,
    DiagnosisFeedbackResponse,
    DiagnosisFeedbackUpsert,
    DiagnosisImagePredictionResponse,
    DiagnosisImageResponse,
    DiagnosisLink,
    IncomingImage,
)
from app.modules.diagnoses.service import DiagnosisService
from app.modules.users.dependencies import get_current_farmer_id

router = APIRouter(prefix="/diagnoses", tags=["leaf-diagnosis"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[DiagnosisService, Depends(get_diagnosis_service)]
AppSettings = Annotated[Settings, Depends(get_app_settings)]


@router.post("", response_model=DiagnosisCaseResponse, status_code=status.HTTP_201_CREATED)
async def create_diagnosis(
    farmer_id: FarmerId,
    service: Service,
    settings: AppSettings,
    images: Annotated[list[UploadFile], File()],
    captured_at: Annotated[list[datetime] | None, Form()] = None,
    plant_name: Annotated[str | None, Form(min_length=1, max_length=100)] = None,
    farm_id: Annotated[UUID | None, Form()] = None,
    plot_id: Annotated[UUID | None, Form()] = None,
    crop_id: Annotated[UUID | None, Form()] = None,
) -> DiagnosisCaseResponse:
    incoming = await _read_images(images, captured_at, settings)
    return await service.create_case(
        farmer_id,
        images=incoming,
        plant_name=plant_name.strip() if plant_name else None,
        link=DiagnosisLink(farm_id=farm_id, plot_id=plot_id, crop_id=crop_id),
    )


@router.post("/{case_id}/retakes", response_model=DiagnosisCaseResponse)
async def add_retakes(
    case_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    settings: AppSettings,
    images: Annotated[list[UploadFile], File()],
    captured_at: Annotated[list[datetime] | None, Form()] = None,
) -> DiagnosisCaseResponse:
    incoming = await _read_images(images, captured_at, settings)
    return await service.add_retakes(farmer_id, case_id, incoming)


@router.get("", response_model=list[DiagnosisCaseResponse])
async def list_diagnoses(
    farmer_id: FarmerId,
    service: Service,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    farm_id: Annotated[UUID | None, Query()] = None,
    plot_id: Annotated[UUID | None, Query()] = None,
    crop_id: Annotated[UUID | None, Query()] = None,
) -> list[DiagnosisCaseResponse]:
    return await service.list_cases(
        farmer_id,
        limit=limit,
        offset=offset,
        farm_id=farm_id,
        plot_id=plot_id,
        crop_id=crop_id,
    )


@router.get("/{case_id}", response_model=DiagnosisCaseResponse)
async def get_diagnosis(
    case_id: UUID,
    farmer_id: FarmerId,
    service: Service,
) -> DiagnosisCaseResponse:
    return await service.get_case(farmer_id, case_id)


@router.get("/{case_id}/assessments", response_model=list[AssessmentHistoryResponse])
async def diagnosis_assessment_history(
    case_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[AssessmentHistoryResponse]:
    return await service.assessment_history(farmer_id, case_id, limit=limit, offset=offset)


@router.get("/{case_id}/images", response_model=list[DiagnosisImageResponse])
async def diagnosis_images(
    case_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[DiagnosisImageResponse]:
    return await service.image_page(farmer_id, case_id, limit=limit, offset=offset)


@router.get(
    "/{case_id}/image-predictions",
    response_model=list[DiagnosisImagePredictionResponse],
)
async def diagnosis_image_predictions(
    case_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[DiagnosisImagePredictionResponse]:
    return await service.image_prediction_page(farmer_id, case_id, limit=limit, offset=offset)


@router.get("/{case_id}/images/{image_id}")
async def get_diagnosis_image(
    case_id: UUID,
    image_id: UUID,
    farmer_id: FarmerId,
    service: Service,
) -> Response:
    content = await service.read_image(farmer_id, case_id, image_id)
    return Response(
        content=content,
        media_type="image/jpeg",
        headers={"Cache-Control": "private, no-store"},
    )


@router.patch("/{case_id}/link", response_model=DiagnosisCaseResponse)
async def link_diagnosis(
    case_id: UUID,
    link: DiagnosisLink,
    farmer_id: FarmerId,
    service: Service,
) -> DiagnosisCaseResponse:
    return await service.link_case(farmer_id, case_id, link)


@router.put("/{case_id}/feedback", response_model=DiagnosisFeedbackResponse)
async def save_feedback(
    case_id: UUID,
    data: DiagnosisFeedbackUpsert,
    farmer_id: FarmerId,
    service: Service,
) -> DiagnosisFeedbackResponse:
    return await service.upsert_feedback(farmer_id, case_id, data)


@router.get("/{case_id}/feedback", response_model=DiagnosisFeedbackResponse | None)
async def get_feedback(
    case_id: UUID,
    farmer_id: FarmerId,
    service: Service,
) -> DiagnosisFeedbackResponse | None:
    return await service.get_feedback(farmer_id, case_id)


@router.delete("/{case_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_diagnosis(
    case_id: UUID,
    farmer_id: FarmerId,
    service: Service,
) -> Response:
    await service.delete_case(farmer_id, case_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


async def _read_images(
    uploads: list[UploadFile],
    captured_at: list[datetime] | None,
    settings: Settings,
) -> list[IncomingImage]:
    if not uploads:
        raise ApplicationError(code="SCAN_IMAGES_REQUIRED", status_code=422)
    if len(uploads) > settings.max_diagnosis_images:
        raise ApplicationError(code="SCAN_TOO_MANY_IMAGES", status_code=413)
    if captured_at is not None and len(captured_at) != len(uploads):
        raise ApplicationError(code="SCAN_IMAGE_TIMESTAMPS_MISMATCH", status_code=422)

    total = 0
    incoming: list[IncomingImage] = []
    try:
        for index, upload in enumerate(uploads):
            content = await upload.read(settings.max_image_bytes + 1)
            if len(content) > settings.max_image_bytes:
                raise ApplicationError(code="SCAN_IMAGE_TOO_LARGE", status_code=413)
            total += len(content)
            if total > settings.max_diagnosis_upload_bytes:
                raise ApplicationError(code="SCAN_UPLOAD_TOO_LARGE", status_code=413)
            timestamp = captured_at[index] if captured_at else datetime.now(tz=UTC)
            if timestamp.tzinfo is None:
                timestamp = timestamp.replace(tzinfo=UTC)
            incoming.append(IncomingImage(content=content, captured_or_uploaded_at=timestamp))
    finally:
        for upload in uploads:
            await upload.close()
    return incoming
