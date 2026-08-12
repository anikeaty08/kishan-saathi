"""Authenticated farm, plot, crop, and activity endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status

from app.modules.farms.dependencies import get_farm_service
from app.modules.farms.schemas import (
    ActivityCreate,
    ActivityResponse,
    ActivityUpdate,
    CropCreate,
    CropResponse,
    CropStageUpdate,
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
    activity_id: UUID, farmer_id: FarmerId, service: Service
) -> Response:
    await service.delete_activity(farmer_id, activity_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
