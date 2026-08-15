"""Authenticated combined plot/crop timeline endpoint."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query

from app.modules.history.dependencies import get_history_service
from app.modules.history.schemas import TimelineCategory, TimelinePage, TimelineQuery
from app.modules.history.service import HistoryService
from app.modules.users.dependencies import get_current_farmer_id

router = APIRouter(tags=["history"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[HistoryService, Depends(get_history_service)]


@router.get("/plots/{plot_id}/timeline", response_model=TimelinePage)
async def plot_timeline(
    plot_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    crop_id: Annotated[UUID | None, Query()] = None,
    category: Annotated[list[TimelineCategory] | None, Query()] = None,
    date_from: Annotated[datetime | None, Query()] = None,
    date_to: Annotated[datetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> TimelinePage:
    return await service.timeline(
        farmer_id,
        plot_id,
        query=TimelineQuery(
            crop_id=crop_id,
            categories=set(category or ()),
            date_from=date_from,
            date_to=date_to,
            limit=limit,
            offset=offset,
        ),
    )
