"""Authentication provider contract."""

from typing import Protocol

from app.core.errors import ApplicationError
from app.core.security import AuthenticatedPrincipal, ExternalIdentity


class AuthProvider(Protocol):
    """Replaceable authentication-provider boundary."""

    async def verify_access_token(self, access_token: str) -> AuthenticatedPrincipal: ...

    async def get_identity(self, access_token: str) -> ExternalIdentity: ...

    async def close(self) -> None: ...


class UnavailableAuthProvider:
    """Fail closed when Cognito settings have not been configured."""

    async def verify_access_token(self, access_token: str) -> AuthenticatedPrincipal:
        del access_token
        raise ApplicationError(code="AUTH_PROVIDER_NOT_CONFIGURED", status_code=503)

    async def get_identity(self, access_token: str) -> ExternalIdentity:
        del access_token
        raise ApplicationError(code="AUTH_PROVIDER_NOT_CONFIGURED", status_code=503)

    async def close(self) -> None:
        return None
