"""Authenticated chat-session and message endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Response, status

from app.core.dependencies import get_auth_context
from app.core.security import AuthContext
from app.modules.chats.dependencies import get_chat_service
from app.modules.chats.schemas import (
    ChatCreate,
    ChatDetailResponse,
    ChatMessageCreate,
    ChatMessagePage,
    ChatResponse,
    ChatScope,
    ChatUpdate,
    SendMessageResponse,
)
from app.modules.chats.service import ChatService
from app.modules.users.dependencies import get_current_farmer_id, get_user_service
from app.modules.users.service import UserServicePort

router = APIRouter(prefix="/chats", tags=["ai-chats"])

FarmerId = Annotated[UUID, Depends(get_current_farmer_id)]
Service = Annotated[ChatService, Depends(get_chat_service)]


@router.post("", response_model=ChatResponse, status_code=status.HTTP_201_CREATED)
async def create_chat(data: ChatCreate, farmer_id: FarmerId, service: Service) -> ChatResponse:
    return await service.create_chat(farmer_id, data)


@router.get("", response_model=list[ChatResponse])
async def list_chats(
    farmer_id: FarmerId,
    service: Service,
    include_archived: Annotated[bool, Query()] = False,
    scope_type: Annotated[ChatScope | None, Query()] = None,
    farm_id: Annotated[UUID | None, Query()] = None,
    plot_id: Annotated[UUID | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[ChatResponse]:
    return await service.list_chats(
        farmer_id,
        include_archived=include_archived,
        scope_type=scope_type.value if scope_type else None,
        farm_id=farm_id,
        plot_id=plot_id,
        limit=limit,
        offset=offset,
    )


@router.get("/{chat_id}", response_model=ChatDetailResponse)
async def get_chat(chat_id: UUID, farmer_id: FarmerId, service: Service) -> ChatDetailResponse:
    return await service.get_chat(farmer_id, chat_id)


@router.get("/{chat_id}/messages", response_model=ChatMessagePage)
async def list_chat_messages(
    chat_id: UUID,
    farmer_id: FarmerId,
    service: Service,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    before_sequence: Annotated[int | None, Query(ge=1)] = None,
) -> ChatMessagePage:
    return await service.message_page(
        farmer_id,
        chat_id,
        limit=limit,
        before_sequence=before_sequence,
    )


@router.patch("/{chat_id}", response_model=ChatResponse)
async def update_chat(
    chat_id: UUID, data: ChatUpdate, farmer_id: FarmerId, service: Service
) -> ChatResponse:
    return await service.update_chat(farmer_id, chat_id, data)


@router.delete("/{chat_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_chat(chat_id: UUID, farmer_id: FarmerId, service: Service) -> Response:
    await service.delete_chat(farmer_id, chat_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{chat_id}/messages", response_model=SendMessageResponse)
async def send_message(
    chat_id: UUID,
    data: ChatMessageCreate,
    farmer_id: FarmerId,
    service: Service,
    context: Annotated[AuthContext, Depends(get_auth_context)],
    user_service: Annotated[UserServicePort, Depends(get_user_service)],
    idempotency_key: Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)],
) -> SendMessageResponse:
    profile = await user_service.get_profile(context)
    return await service.send_message(
        farmer_id,
        chat_id,
        data,
        preferred_language=profile.preferred_language,
        idempotency_key=idempotency_key,
    )
