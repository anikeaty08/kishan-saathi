"""Public account endpoints; passwords never leave this provider boundary."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response, status

from app.core.dependencies import get_auth_rate_limiter
from app.core.rate_limits import AuthRateLimiter
from app.integrations.auth.accounts import AccountAuthProvider
from app.modules.auth.dependencies import get_account_auth_provider
from app.modules.auth.schemas import (
    AuthTokensResponse,
    ConfirmationRequest,
    EmailRequest,
    PasswordRequest,
    PasswordResetConfirmationRequest,
    RefreshRequest,
    SignUpRequest,
    SignUpResponse,
)
from app.modules.auth.service import AuthService

router = APIRouter(prefix="/auth", tags=["authentication"])
Provider = Annotated[AccountAuthProvider, Depends(get_account_auth_provider)]
Limiter = Annotated[AuthRateLimiter, Depends(get_auth_rate_limiter)]


@asynccontextmanager
async def _limit(
    request: Request,
    email_or_token: str,
    limiter: AuthRateLimiter,
) -> AsyncIterator[None]:
    account_key = limiter.subject_key(
        f"auth-account:{email_or_token.strip().lower()}"
    )
    remote = request.client.host if request.client is not None else "unknown"
    remote_key = limiter.subject_key(f"auth-ip:{remote}")
    async with limiter.request(account_key), limiter.ip_request(remote_key):
        yield


def _private(response: Response) -> None:
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Pragma"] = "no-cache"


@router.post("/sign-up", response_model=SignUpResponse, status_code=status.HTTP_201_CREATED)
async def sign_up(
    data: SignUpRequest,
    request: Request,
    response: Response,
    provider: Provider,
    limiter: Limiter,
) -> SignUpResponse:
    async with _limit(request, str(data.email), limiter):
        confirmed = await AuthService(provider).sign_up(
            data.name, str(data.email), data.password.get_secret_value()
        )
    _private(response)
    return SignUpResponse(confirmed=confirmed)


@router.post("/confirm", status_code=status.HTTP_204_NO_CONTENT)
async def confirm(
    data: ConfirmationRequest,
    request: Request,
    response: Response,
    provider: Provider,
    limiter: Limiter,
) -> Response:
    async with _limit(request, str(data.email), limiter):
        await AuthService(provider).confirm(str(data.email), data.code.get_secret_value())
    _private(response)
    response.status_code = status.HTTP_204_NO_CONTENT
    return response


@router.post("/resend", status_code=status.HTTP_204_NO_CONTENT)
async def resend(
    data: EmailRequest,
    request: Request,
    response: Response,
    provider: Provider,
    limiter: Limiter,
) -> Response:
    async with _limit(request, str(data.email), limiter):
        await AuthService(provider).resend(str(data.email))
    _private(response)
    response.status_code = status.HTTP_204_NO_CONTENT
    return response


@router.post("/sign-in", response_model=AuthTokensResponse)
async def sign_in(
    data: PasswordRequest,
    request: Request,
    response: Response,
    provider: Provider,
    limiter: Limiter,
) -> AuthTokensResponse:
    async with _limit(request, str(data.email), limiter):
        result = await AuthService(provider).sign_in(
            str(data.email), data.password.get_secret_value()
        )
    _private(response)
    return result


@router.post("/refresh", response_model=AuthTokensResponse)
async def refresh(
    data: RefreshRequest,
    request: Request,
    response: Response,
    provider: Provider,
    limiter: Limiter,
) -> AuthTokensResponse:
    token = data.refresh_token.get_secret_value()
    async with _limit(request, token[-32:], limiter):
        result = await AuthService(provider).refresh(token)
    _private(response)
    return result


@router.post("/password-reset", status_code=status.HTTP_204_NO_CONTENT)
async def password_reset(
    data: EmailRequest,
    request: Request,
    response: Response,
    provider: Provider,
    limiter: Limiter,
) -> Response:
    async with _limit(request, str(data.email), limiter):
        await AuthService(provider).request_password_reset(str(data.email))
    _private(response)
    response.status_code = status.HTTP_204_NO_CONTENT
    return response


@router.post("/password-reset/confirm", status_code=status.HTTP_204_NO_CONTENT)
async def password_reset_confirm(
    data: PasswordResetConfirmationRequest,
    request: Request,
    response: Response,
    provider: Provider,
    limiter: Limiter,
) -> Response:
    async with _limit(request, str(data.email), limiter):
        await AuthService(provider).confirm_password_reset(
            str(data.email),
            data.code.get_secret_value(),
            data.new_password.get_secret_value(),
        )
    _private(response)
    response.status_code = status.HTTP_204_NO_CONTENT
    return response
