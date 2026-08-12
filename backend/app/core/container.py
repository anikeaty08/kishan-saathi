"""Startup dependency container and provider/plugin bindings."""

from app.core.config import Settings
from app.integrations.auth.cognito import CognitoAuthProvider
from app.integrations.auth.provider import AuthProvider, UnavailableAuthProvider


def build_auth_provider(settings: Settings) -> AuthProvider:
    """Select the configured authentication adapter once during startup."""

    if not settings.cognito_user_pool_id or not settings.cognito_app_client_id:
        return UnavailableAuthProvider()
    return CognitoAuthProvider(settings)
