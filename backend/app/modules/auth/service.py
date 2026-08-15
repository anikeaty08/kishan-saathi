"""Provider-neutral authentication lifecycle orchestration."""

from app.integrations.auth.accounts import AccountAuthProvider
from app.modules.auth.schemas import AuthTokensResponse


class AuthService:
    def __init__(self, provider: AccountAuthProvider) -> None:
        self._provider = provider

    async def sign_up(self, name: str, email: str, password: str) -> bool:
        return await self._provider.sign_up(
            " ".join(name.split()), email.strip().lower(), password
        )

    async def confirm(self, email: str, code: str) -> None:
        await self._provider.confirm_sign_up(email.strip().lower(), code.strip())

    async def resend(self, email: str) -> None:
        await self._provider.resend_confirmation(email.strip().lower())

    async def sign_in(self, email: str, password: str) -> AuthTokensResponse:
        tokens = await self._provider.sign_in(email.strip().lower(), password)
        return AuthTokensResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            id_token=tokens.id_token,
            expires_in=tokens.expires_in,
        )

    async def refresh(self, refresh_token: str) -> AuthTokensResponse:
        tokens = await self._provider.refresh(refresh_token)
        return AuthTokensResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            id_token=tokens.id_token,
            expires_in=tokens.expires_in,
        )

    async def request_password_reset(self, email: str) -> None:
        await self._provider.request_password_reset(email.strip().lower())

    async def confirm_password_reset(
        self, email: str, code: str, new_password: str
    ) -> None:
        await self._provider.confirm_password_reset(
            email.strip().lower(), code.strip(), new_password
        )
