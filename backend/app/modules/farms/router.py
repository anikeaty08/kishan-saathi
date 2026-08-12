"""Authenticated farm, plot, crop, and activity endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Query, Response, UploadFile, status

from app.core.config import Settings
from app.core.dependencies import get_app_settings
from app.core.errors import ApplicationError
from app.modules.farms.dependencies import get_activity_photo_service, get_farm_service
from app.modules.farms.photos import ActivityPhotoService
from app.modules.farms.schemas import (
    ActivityCreate,
    ActivityPhotoResponse,
    ActivityResponse,
    ActivityUpdate,
    CropCreate,
    CropResponse,
    CropStageUpdate,
    DeletionImpactResponse,
    FarmCreate,
    FarmResponse,
    FarmUpdate,
    PlotCreate,
    PlotResponse,
    PlotUpdate,
)
from app.modules.farms.service import FarmService
from app.modules.users.dependencies import get_current_farmer_id

router = APIRouter(tags=["farm-organization"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[FarmService, Depends(get_farm_service)]
PhotoService = Annotated[ActivityPhotoService, Depends(get_activity_photo_service)]
AppSettings = Annotated[Settings, Depends(get_app_settings)]


@router.post("/farms", response_model=FarmResponse, status_code=status.HTTP_201_CREATED)
async def create_farm(data: FarmCreate, farmer_id: FarmerId, service: Service) -> FarmResponse:
    return await service.create_farm(farmer_id, data)


@router.get("/farms", response_model=list[FarmResponse])
async def list_farms(farmer_id: FarmerId, service: Service) -> list[FarmResponse]:
    return await service.list_farms(farmer_id)


@router.put("/farms/{farm_id}", response_model=FarmResponse)
async def update_farm(
    farm_id: UUID, data: FarmUpdate, farmer_id: FarmerId, service: Service
) -> FarmResponse:
    return await service.update_farm(farmer_id, farm_id, data)


@router.delete("/farms/{farm_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_farm(
    farm_id: UUID, farmer_id: FarmerId, service: Service
) -> Response:
    await service.delete_farm(farmer_id, farm_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/farms/{farm_id}/deletion-impact", response_model=DeletionImpactResponse)
async def farm_deletion_impact(
    farm_id: UUID, farmer_id: FarmerId, service: Service
) -> DeletionImpactResponse:
    return await service.farm_deletion_impact(farmer_id, farm_id)


@router.post("/plots", response_model=PlotResponse, status_code=status.HTTP_201_CREATED)
async def create_plot(data: PlotCreate, farmer_id: FarmerId, service: Service) -> PlotResponse:
    return await service.create_plot(farmer_id, data)


@router.get("/plots", response_model=list[PlotResponse])
async def list_plots(
    farmer_id: FarmerId,
    service: Service,
    farm_id: Annotated[UUID | None, Query()] = None,
) -> list[PlotResponse]:
    return await service.list_plots(farmer_id, farm_id)


@router.get("/plots/{plot_id}", response_model=PlotResponse)
async def get_plot(plot_id: UUID, farmer_id: FarmerId, service: Service) -> PlotResponse:
    return await service.get_plot(farmer_id, plot_id)


@router.patch("/plots/{plot_id}", response_model=PlotResponse)
async def update_plot(
    plot_id: UUID, data: PlotUpdate, farmer_id: FarmerId, service: Service
) -> PlotResponse:
    return await service.update_plot(farmer_id, plot_id, data)


@router.delete("/plots/{plot_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_plot(
    plot_id: UUID, farmer_id: FarmerId, service: Service
) -> Response:
    await service.delete_plot(farmer_id, plot_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/plots/{plot_id}/deletion-impact", response_model=DeletionImpactResponse)
async def plot_deletion_impact(
    plot_id: UUID, farmer_id: FarmerId, service: Service
) -> DeletionImpactResponse:
    return await service.plot_deletion_impact(farmer_id, plot_id)


@router.post(
    "/plots/{plot_id}/crops",
    response_model=CropResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_crop(
    plot_id: UUID, data: CropCreate, farmer_id: FarmerId, service: Service
) -> CropResponse:
    return await service.add_crop(farmer_id, plot_id, data)


@router.patch("/crops/{crop_id}/stage", response_model=CropResponse)
async def update_crop_stage(
    crop_id: UUID, data: CropStageUpdate, farmer_id: FarmerId, service: Service
) -> CropResponse:
    return await service.update_crop_stage(farmer_id, crop_id, data)


@router.delete("/crops/{crop_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_crop(
    crop_id: UUID, farmer_id: FarmerId, service: Service
) -> Response:
    await service.delete_crop(farmer_id, crop_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/crops/{crop_id}/deletion-impact", response_model=DeletionImpactResponse)
async def crop_deletion_impact(
    crop_id: UUID, farmer_id: FarmerId, service: Service
) -> DeletionImpactResponse:
    return await service.crop_deletion_impact(farmer_id, crop_id)


@router.post(
    "/plots/{plot_id}/activities",
    response_model=ActivityResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_activity(
    plot_id: UUID, data: ActivityCreate, farmer_id: FarmerId, service: Service
) -> ActivityResponse:
    return await service.create_activity(farmer_id, plot_id, data)


@router.patch("/activities/{activity_id}", response_model=ActivityResponse)
async def update_activity(
    activity_id: UUID,
    data: ActivityUpdate,
    farmer_id: FarmerId,
    service: Service,
) -> ActivityResponse:
    return await service.update_activity(farmer_id, activity_id, data)


@router.delete("/activities/{activity_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_activity(
    activity_id: UUID, farmer_id: FarmerId, service: PhotoService
) -> Response:
    await service.delete_activity(farmer_id, activity_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/activities/{activity_id}/photos",
    response_model=ActivityPhotoResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_activity_photo(
    activity_id: UUID,
    photo: Annotated[UploadFile, File()],
    farmer_id: FarmerId,
    service: PhotoService,
    settings: AppSettings,
) -> ActivityPhotoResponse:
    try:
        content = await photo.read(settings.max_image_bytes + 1)
    finally:
        await photo.close()
    if len(content) > settings.max_image_bytes:
        raise ApplicationError(code="ACTIVITY_PHOTO_TOO_LARGE", status_code=413)
    return await service.add(farmer_id, activity_id, content)


@router.get(
    "/activities/{activity_id}/photos", response_model=list[ActivityPhotoResponse]
)
async def list_activity_photos(
    activity_id: UUID, farmer_id: FarmerId, service: PhotoService
) -> list[ActivityPhotoResponse]:
    return await service.list(farmer_id, activity_id)


@router.get("/activities/{activity_id}/photos/{photo_id}")
async def get_activity_photo(
    activity_id: UUID,
    photo_id: UUID,
    farmer_id: FarmerId,
    service: PhotoService,
) -> Response:
    return Response(
        content=await service.read(farmer_id, activity_id, photo_id),
        media_type="image/jpeg",
        headers={"Cache-Control": "private, no-store"},
    )


@router.delete(
    "/activities/{activity_id}/photos/{photo_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_activity_photo(
    activity_id: UUID,
    photo_id: UUID,
    farmer_id: FarmerId,
    service: PhotoService,
) -> Response:
    await service.delete(farmer_id, activity_id, photo_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
