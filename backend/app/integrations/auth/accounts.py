"""Public account-lifecycle provider contract used by FastAPI auth routes."""

from dataclasses import dataclass
from typing import Protocol

from app.core.errors import ApplicationError


@dataclass(frozen=True, slots=True)
class AuthTokens:
    access_token: str
    refresh_token: str
    id_token: str | None
    expires_in: int


class AccountAuthProvider(Protocol):
    async def sign_up(self, name: str, email: str, password: str) -> bool: ...

    async def confirm_sign_up(self, email: str, code: str) -> None: ...

    async def resend_confirmation(self, email: str) -> None: ...

    async def sign_in(self, email: str, password: str) -> AuthTokens: ...

    async def refresh(self, refresh_token: str) -> AuthTokens: ...

    async def request_password_reset(self, email: str) -> None: ...

    async def confirm_password_reset(
        self, email: str, code: str, new_password: str
    ) -> None: ...

    async def close(self) -> None: ...


class UnavailableAccountAuthProvider:
    """Fail closed when account lifecycle configuration is absent."""

    async def _unavailable(self) -> None:
        raise ApplicationError(code="AUTH_NOT_CONFIGURED", status_code=503)

    async def sign_up(self, name: str, email: str, password: str) -> bool:
        await self._unavailable()
        return False

    async def confirm_sign_up(self, email: str, code: str) -> None:
        await self._unavailable()

    async def resend_confirmation(self, email: str) -> None:
        await self._unavailable()

    async def sign_in(self, email: str, password: str) -> AuthTokens:
        await self._unavailable()
        raise AssertionError("unreachable")

    async def refresh(self, refresh_token: str) -> AuthTokens:
        await self._unavailable()
        raise AssertionError("unreachable")

    async def request_password_reset(self, email: str) -> None:
        await self._unavailable()

    async def confirm_password_reset(
        self, email: str, code: str, new_password: str
    ) -> None:
        await self._unavailable()

    async def close(self) -> None:
        return None
