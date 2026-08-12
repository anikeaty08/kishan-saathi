"""Business rules for farms, plots, crops, and manual activities."""

from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy.exc import IntegrityError

from app.core.errors import ApplicationError
from app.modules.farms.models import Activity, Crop, CropStageEvent, Farm, Plot
from app.modules.farms.repository import FarmRepository
from app.modules.farms.schemas import (
    ActivityCreate,
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


class FarmService:
    """Enforce ownership and aggregate invariants before persistence."""

    def __init__(self, repository: FarmRepository) -> None:
        self.repository = repository

    async def create_farm(self, farmer_id: UUID, data: FarmCreate) -> FarmResponse:
        farm = Farm(farmer_id=farmer_id, name=data.name)
        self.repository.add(farm)
        await self._commit_unique("FARM_NAME_ALREADY_EXISTS")
        await self.repository.refresh(farm)
        return FarmResponse.model_validate(farm)

    async def list_farms(self, farmer_id: UUID) -> list[FarmResponse]:
        farms = await self.repository.list_farms(farmer_id)
        return [FarmResponse.model_validate(item) for item in farms]

    async def update_farm(
        self, farmer_id: UUID, farm_id: UUID, data: FarmUpdate
    ) -> FarmResponse:
        farm = await self._farm(farmer_id, farm_id)
        farm.name = data.name
        await self._commit_unique("FARM_NAME_ALREADY_EXISTS")
        await self.repository.refresh(farm)
        return FarmResponse.model_validate(farm)

    async def delete_farm(self, farmer_id: UUID, farm_id: UUID) -> None:
        farm = await self._farm(farmer_id, farm_id)
        impact = await self.farm_deletion_impact(farmer_id, farm_id)
        if not impact.can_delete:
            raise ApplicationError(code="FARM_HAS_LINKED_DATA", status_code=409)
        await self.repository.delete(farm)
        await self.repository.commit()

    async def create_plot(self, farmer_id: UUID, data: PlotCreate) -> PlotResponse:
        if data.farm_id is not None:
            await self._farm(farmer_id, data.farm_id)
        plot = Plot(
            farmer_id=farmer_id,
            farm_id=data.farm_id,
            name=data.name,
            latitude=data.latitude,
            longitude=data.longitude,
            location_label=data.location_label,
            area_value=data.area_value,
            area_unit=data.area_unit.value if data.area_unit else None,
            soil_notes=data.soil_notes,
            irrigation_details=data.irrigation_details,
        )
        self.repository.add(plot)
        await self.repository.session.flush()
        for crop_data in data.crops:
            self._add_crop(farmer_id, plot.id, crop_data)
        await self._commit_unique("PLOT_NAME_ALREADY_EXISTS")
        await self.repository.refresh(plot)
        return await self._plot_response(farmer_id, plot)

    async def list_plots(
        self, farmer_id: UUID, farm_id: UUID | None
    ) -> list[PlotResponse]:
        if farm_id is not None:
            await self._farm(farmer_id, farm_id)
        plots = await self.repository.list_plots(farmer_id, farm_id)
        return [await self._plot_response(farmer_id, plot) for plot in plots]

    async def get_plot(self, farmer_id: UUID, plot_id: UUID) -> PlotResponse:
        return await self._plot_response(farmer_id, await self._plot(farmer_id, plot_id))

    async def update_plot(
        self, farmer_id: UUID, plot_id: UUID, data: PlotUpdate
    ) -> PlotResponse:
        plot = await self._plot(farmer_id, plot_id)
        if "farm_id" in data.model_fields_set and data.farm_id is not None:
            await self._farm(farmer_id, data.farm_id)
        for field in data.model_fields_set:
            value = getattr(data, field)
            if field == "area_unit" and value is not None:
                value = value.value
            setattr(plot, field, value)
        await self._commit_unique("PLOT_NAME_ALREADY_EXISTS")
        await self.repository.refresh(plot)
        return await self._plot_response(farmer_id, plot)

    async def add_crop(
        self, farmer_id: UUID, plot_id: UUID, data: CropCreate
    ) -> CropResponse:
        await self._plot(farmer_id, plot_id)
        crop = self._add_crop(farmer_id, plot_id, data)
        await self.repository.commit()
        await self.repository.refresh(crop)
        return CropResponse.model_validate(crop)

    async def update_crop_stage(
        self, farmer_id: UUID, crop_id: UUID, data: CropStageUpdate
    ) -> CropResponse:
        crop = await self._crop(farmer_id, crop_id)
        crop.stage = data.stage
        self.repository.add(
            CropStageEvent(
                farmer_id=farmer_id,
                crop_id=crop.id,
                stage=data.stage,
                observed_at=datetime.now(tz=UTC),
            )
        )
        await self.repository.commit()
        await self.repository.refresh(crop)
        return CropResponse.model_validate(crop)

    async def delete_plot(self, farmer_id: UUID, plot_id: UUID) -> None:
        plot = await self._plot(farmer_id, plot_id)
        impact = await self.plot_deletion_impact(farmer_id, plot_id)
        if not impact.can_delete:
            raise ApplicationError(code="PLOT_HAS_LINKED_DATA", status_code=409)
        await self.repository.delete(plot)
        await self.repository.commit()

    async def delete_crop(self, farmer_id: UUID, crop_id: UUID) -> None:
        crop = await self._crop(farmer_id, crop_id)
        impact = await self.crop_deletion_impact(farmer_id, crop_id)
        if not impact.can_delete:
            raise ApplicationError(code="CROP_HAS_LINKED_DATA", status_code=409)
        await self.repository.delete(crop)
        await self.repository.commit()

    async def farm_deletion_impact(
        self, farmer_id: UUID, farm_id: UUID
    ) -> DeletionImpactResponse:
        await self._farm(farmer_id, farm_id)
        return self._impact(
            farm_id, await self.repository.farm_linked_record_counts(farmer_id, farm_id)
        )

    async def plot_deletion_impact(
        self, farmer_id: UUID, plot_id: UUID
    ) -> DeletionImpactResponse:
        await self._plot(farmer_id, plot_id)
        return self._impact(
            plot_id, await self.repository.plot_linked_record_counts(farmer_id, plot_id)
        )

    async def crop_deletion_impact(
        self, farmer_id: UUID, crop_id: UUID
    ) -> DeletionImpactResponse:
        await self._crop(farmer_id, crop_id)
        return self._impact(
            crop_id, await self.repository.crop_linked_record_counts(farmer_id, crop_id)
        )

    @staticmethod
    def _impact(entity_id: UUID, counts: dict[str, int]) -> DeletionImpactResponse:
        return DeletionImpactResponse(
            entity_id=entity_id,
            can_delete=not any(counts.values()),
            linked_records=counts,
        )

    async def create_activity(
        self, farmer_id: UUID, plot_id: UUID, data: ActivityCreate
    ) -> ActivityResponse:
        await self._plot(farmer_id, plot_id)
        if data.crop_id is not None:
            crop = await self._crop(farmer_id, data.crop_id)
            if crop.plot_id != plot_id:
                raise ApplicationError(code="CROP_NOT_IN_PLOT", status_code=409)
        activity = Activity(
            farmer_id=farmer_id,
            plot_id=plot_id,
            crop_id=data.crop_id,
            title=data.title,
            notes=data.notes,
            occurred_at=data.occurred_at,
        )
        self.repository.add(activity)
        await self.repository.commit()
        await self.repository.refresh(activity)
        return ActivityResponse.model_validate(activity)

    async def update_activity(
        self, farmer_id: UUID, activity_id: UUID, data: ActivityUpdate
    ) -> ActivityResponse:
        activity = await self._activity(farmer_id, activity_id)
        for field in data.model_fields_set:
            setattr(activity, field, getattr(data, field))
        await self.repository.commit()
        await self.repository.refresh(activity)
        return ActivityResponse.model_validate(activity)

    async def delete_activity(self, farmer_id: UUID, activity_id: UUID) -> None:
        await self.repository.delete(await self._activity(farmer_id, activity_id))
        await self.repository.commit()

    def _add_crop(self, farmer_id: UUID, plot_id: UUID, data: CropCreate) -> Crop:
        crop_id = uuid4()
        crop = Crop(
            id=crop_id,
            farmer_id=farmer_id,
            plot_id=plot_id,
            name=data.name,
            stage=data.stage,
            variety=data.variety,
            sowing_or_transplant_date=data.sowing_or_transplant_date,
        )
        self.repository.add(crop)
        self.repository.add(
            CropStageEvent(farmer_id=farmer_id, crop_id=crop_id, stage=crop.stage)
        )
        return crop

    async def _plot_response(self, farmer_id: UUID, plot: Plot) -> PlotResponse:
        crops = await self.repository.list_crops(farmer_id, plot.id)
        return PlotResponse(
            **PlotResponse.model_validate(plot).model_dump(exclude={"crops"}),
            crops=[CropResponse.model_validate(crop) for crop in crops],
        )

    async def _farm(self, farmer_id: UUID, farm_id: UUID) -> Farm:
        farm = await self.repository.get_farm(farmer_id, farm_id)
        if farm is None:
            raise ApplicationError(code="FARM_NOT_FOUND", status_code=404)
        return farm

    async def _plot(self, farmer_id: UUID, plot_id: UUID) -> Plot:
        plot = await self.repository.get_plot(farmer_id, plot_id)
        if plot is None:
            raise ApplicationError(code="PLOT_NOT_FOUND", status_code=404)
        return plot

    async def _crop(self, farmer_id: UUID, crop_id: UUID) -> Crop:
        crop = await self.repository.get_crop(farmer_id, crop_id)
        if crop is None:
            raise ApplicationError(code="CROP_NOT_FOUND", status_code=404)
        return crop

    async def _activity(self, farmer_id: UUID, activity_id: UUID) -> Activity:
        activity = await self.repository.get_activity(farmer_id, activity_id)
        if activity is None:
            raise ApplicationError(code="ACTIVITY_NOT_FOUND", status_code=404)
        return activity

    async def _commit_unique(self, code: str) -> None:
        try:
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.session.rollback()
            raise ApplicationError(code=code, status_code=409) from exc
