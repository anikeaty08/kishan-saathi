"""Authenticated memory connection and farmer-control endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.dependencies import get_paid_operation_rate_limiter
from app.core.rate_limits import PaidOperationRateLimiter
from app.modules.memories.dependencies import get_memory_service
from app.modules.memories.schemas import (
    ChatMemoryConnectionCreate,
    ChatMemoryConnectionResponse,
    MemoryFactResponse,
)
from app.modules.memories.service import MemoryService
from app.modules.users.dependencies import get_current_farmer_id

router = APIRouter(tags=["memory"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[MemoryService, Depends(get_memory_service)]


@router.post(
    "/chats/{chat_id}/memory-connection",
    response_model=ChatMemoryConnectionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def connect_general_chat(
    chat_id: UUID,
    data: ChatMemoryConnectionCreate,
    farmer_id: FarmerId,
    service: Service,
    limiter: Annotated[PaidOperationRateLimiter, Depends(get_paid_operation_rate_limiter)],
) -> ChatMemoryConnectionResponse:
    async with limiter.request(farmer_id, "memory_connection"):
        return await service.connect_chat(farmer_id, chat_id, data)


@router.get("/farms/{farm_id}/memories", response_model=list[MemoryFactResponse])
async def list_farm_memories(
    farm_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limit: int = Query(default=100, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> list[MemoryFactResponse]:
    return await service.list_farm(farmer_id, farm_id, limit=limit, offset=offset)


@router.get("/plots/{plot_id}/memories", response_model=list[MemoryFactResponse])
async def list_plot_memories(
    plot_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limit: int = Query(default=100, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> list[MemoryFactResponse]:
    return await service.list_plot(farmer_id, plot_id, limit=limit, offset=offset)


@router.delete("/memories/{fact_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_memory(fact_id: UUID, farmer_id: FarmerId, service: Service) -> Response:
    await service.delete_fact(farmer_id, fact_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/memories/{fact_id}/retry", response_model=MemoryFactResponse)
async def retry_memory_index(
    fact_id: UUID, farmer_id: FarmerId, service: Service
) -> MemoryFactResponse:
    return await service.retry_fact(farmer_id, fact_id)


@router.delete("/chats/{chat_id}/memory-connection", status_code=status.HTTP_204_NO_CONTENT)
async def disconnect_general_chat(chat_id: UUID, farmer_id: FarmerId, service: Service) -> Response:
    await service.disconnect_chat(farmer_id, chat_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
