"""Farmer-owned retry control for pending privacy deletions."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.modules.storage_cleanup.dependencies import get_object_cleanup_service
from app.modules.storage_cleanup.service import ObjectCleanupService
from app.modules.users.dependencies import get_current_farmer_id

router = APIRouter(prefix="/privacy", tags=["privacy"])


class CleanupRetryResponse(BaseModel):
    attempted: int


@router.post("/object-deletions/retry", response_model=CleanupRetryResponse)
async def retry_object_deletions(
    farmer_id: Annotated[UUID, Depends(get_current_farmer_id)],
    service: Annotated[ObjectCleanupService, Depends(get_object_cleanup_service)],
) -> CleanupRetryResponse:
    return CleanupRetryResponse(attempted=await service.retry_owner(farmer_id))
