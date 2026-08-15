"""Plot and crop timeline composition use cases."""

from uuid import UUID

from app.core.errors import ApplicationError
from app.modules.farms.repository import FarmRepository
from app.modules.history.repository import HistoryRepository
from app.modules.history.schemas import TimelineCategory, TimelinePage, TimelineQuery


class HistoryService:
    def __init__(self, repository: HistoryRepository, farms: FarmRepository) -> None:
        self._repository = repository
        self._farms = farms

    async def timeline(
        self,
        farmer_id: UUID,
        plot_id: UUID,
        *,
        query: TimelineQuery,
    ) -> TimelinePage:
        if await self._farms.get_plot(farmer_id, plot_id) is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        if query.crop_id is not None:
            crop = await self._farms.get_crop(farmer_id, query.crop_id)
            if crop is None:
                raise ApplicationError(code="CROP_NOT_FOUND", status_code=404)
            if crop.plot_id != plot_id:
                raise ApplicationError(code="CROP_NOT_IN_PLOT", status_code=409)
        if (
            query.date_from is not None
            and query.date_to is not None
            and query.date_from > query.date_to
        ):
            raise ApplicationError(code="TIMELINE_DATE_RANGE_INVALID", status_code=422)
        selected = query.categories or set(TimelineCategory)
        requested = query.limit + query.offset + 1
        values = await self._repository.timeline(
            farmer_id,
            plot_id,
            crop_id=query.crop_id,
            categories=selected,
            date_from=query.date_from,
            date_to=query.date_to,
            per_category_limit=requested,
        )
        values.sort(key=lambda item: (item.occurred_at, item.id), reverse=True)
        page = values[query.offset : query.offset + query.limit]
        return TimelinePage(
            items=page,
            limit=query.limit,
            offset=query.offset,
            has_more=len(values) > query.offset + query.limit,
        )
