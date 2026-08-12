"""Startup dependency container and provider/plugin bindings."""

from app.core.config import Settings
from app.integrations.auth.cognito import CognitoAuthProvider
from app.integrations.auth.provider import AuthProvider, UnavailableAuthProvider
from app.integrations.inference.provider import (
    LeafInferenceProvider,
    UnavailableLeafInferenceProvider,
)
from app.integrations.storage.local import LocalObjectStorage
from app.integrations.storage.provider import ObjectStorageProvider


def build_auth_provider(settings: Settings) -> AuthProvider:
    """Select the configured authentication adapter once during startup."""

    if not settings.cognito_configured:
        return UnavailableAuthProvider()
    return CognitoAuthProvider(settings)


def build_object_storage(settings: Settings) -> ObjectStorageProvider:
    """Select local private storage until an S3 adapter is configured."""

    return LocalObjectStorage(settings.local_storage_path)


def build_leaf_inference_provider(_settings: Settings) -> LeafInferenceProvider:
    """Fail honestly until the evaluated checkpoint or service is supplied."""

    return UnavailableLeafInferenceProvider()
