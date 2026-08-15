"""Authenticated reminder proposal and in-app task endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.reminders.dependencies import get_reminder_service
from app.modules.reminders.schemas import (
    ProposalDecision,
    ProposalDecisionResponse,
    ProposalResponse,
    ReminderActionRequest,
    ReminderCreate,
    ReminderEventResponse,
    ReminderResponse,
)
from app.modules.reminders.service import ReminderService
from app.modules.users.dependencies import get_current_farmer_id

router = APIRouter(tags=["reminders"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[ReminderService, Depends(get_reminder_service)]


@router.get("/reminder-proposals", response_model=list[ProposalResponse])
async def list_reminder_proposals(
    farmer_id: FarmerId,
    service: Service,
    pending_only: Annotated[bool, Query()] = True,
) -> list[ProposalResponse]:
    return await service.list_proposals(farmer_id, pending_only=pending_only)


@router.post(
    "/reminder-proposals/{proposal_id}/decision",
    response_model=ProposalDecisionResponse,
)
async def decide_reminder_proposal(
    proposal_id: UUID,
    data: ProposalDecision,
    farmer_id: FarmerId,
    service: Service,
) -> ProposalDecisionResponse:
    """Create a task only when the farmer explicitly accepts the proposal."""

    return await service.decide_proposal(farmer_id, proposal_id, accepted=data.accepted)


@router.post("/reminders", response_model=ReminderResponse, status_code=status.HTTP_201_CREATED)
async def create_manual_reminder(
    data: ReminderCreate, farmer_id: FarmerId, service: Service
) -> ReminderResponse:
    return await service.create_manual(farmer_id, data)


@router.get("/reminders", response_model=list[ReminderResponse])
async def list_reminders(
    farmer_id: FarmerId,
    service: Service,
    include_finished: Annotated[bool, Query()] = False,
) -> list[ReminderResponse]:
    return await service.list_reminders(farmer_id, include_finished=include_finished)


@router.post("/reminders/{reminder_id}/actions", response_model=ReminderResponse)
async def apply_reminder_action(
    reminder_id: UUID,
    data: ReminderActionRequest,
    farmer_id: FarmerId,
    service: Service,
) -> ReminderResponse:
    return await service.apply_action(farmer_id, reminder_id, data)


@router.get("/reminders/{reminder_id}/events", response_model=list[ReminderEventResponse])
async def list_reminder_events(
    reminder_id: UUID, farmer_id: FarmerId, service: Service
) -> list[ReminderEventResponse]:
    return await service.list_events(farmer_id, reminder_id)
