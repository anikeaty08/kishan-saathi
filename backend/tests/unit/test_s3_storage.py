"""Tests for private, owner-bound S3 storage."""

from typing import Any, cast
from uuid import UUID

import pytest
from mypy_boto3_s3 import S3Client

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.storage.s3 import S3ObjectStorage

OWNER = UUID("00000000-0000-0000-0000-000000000001")
OTHER = UUID("00000000-0000-0000-0000-000000000002")


class FakeBody:
    def __init__(self, content: bytes) -> None:
        self.content = content
        self.closed = False

    def read(self, amount: int | None = None) -> bytes:
        return self.content if amount is None else self.content[:amount]

    def close(self) -> None:
        self.closed = True


class FakeS3Client:
    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}
        self.last_put: dict[str, Any] = {}
        self.closed = False

    def put_object(self, **kwargs: Any) -> dict[str, object]:
        self.last_put = kwargs
        self.objects[str(kwargs["Key"])] = cast(bytes, kwargs["Body"])
        return {}

    def get_object(self, **kwargs: Any) -> dict[str, object]:
        content = self.objects[str(kwargs["Key"])]
        return {"Body": FakeBody(content), "ContentLength": len(content)}

    def delete_object(self, **kwargs: Any) -> dict[str, object]:
        self.objects.pop(str(kwargs["Key"]), None)
        return {}

    def close(self) -> None:
        self.closed = True


def storage(client: FakeS3Client, *, kms_key: str = "") -> S3ObjectStorage:
    return S3ObjectStorage(
        Settings(
            _env_file=None,
            storage_backend="s3",
            s3_bucket="farmer-images",
            s3_key_prefix="private",
            s3_kms_key_id=kms_key,
            s3_expected_bucket_owner="123456789012",
        ),
        client=cast(S3Client, client),
    )


@pytest.mark.asyncio
async def test_s3_storage_uses_private_owner_key_and_encryption() -> None:
    client = FakeS3Client()
    provider = storage(client, kms_key="alias/krishisathi-images")

    stored = await provider.put_private_image(
        owner_id=OWNER,
        category="diagnoses",
        content=b"private-image",
    )

    assert stored.key.startswith(f"private/{OWNER}/diagnoses/")
    assert client.last_put["Bucket"] == "farmer-images"
    assert client.last_put["CacheControl"] == "private, no-store"
    assert client.last_put["ServerSideEncryption"] == "aws:kms"
    assert client.last_put["SSEKMSKeyId"] == "alias/krishisathi-images"
    assert client.last_put["BucketKeyEnabled"] is True
    assert client.last_put["ExpectedBucketOwner"] == "123456789012"
    assert await provider.read_private(owner_id=OWNER, key=stored.key) == b"private-image"


@pytest.mark.asyncio
async def test_s3_storage_rejects_cross_owner_read_and_delete() -> None:
    client = FakeS3Client()
    provider = storage(client)
    stored = await provider.put_private_image(
        owner_id=OWNER,
        category="activities",
        content=b"private-image",
    )

    with pytest.raises(ApplicationError) as read_error:
        await provider.read_private(owner_id=OTHER, key=stored.key)
    assert read_error.value.code == "STORAGE_OBJECT_NOT_FOUND"

    with pytest.raises(ApplicationError) as delete_error:
        await provider.delete_private(owner_id=OTHER, key=stored.key)
    assert delete_error.value.code == "STORAGE_OBJECT_NOT_FOUND"
    assert stored.key in client.objects

    await provider.delete_private(owner_id=OWNER, key=stored.key)
    assert stored.key not in client.objects


def test_production_configuration_fails_closed_without_private_s3() -> None:
    with pytest.raises(ValueError, match="PRODUCTION_REQUIRES_S3_STORAGE"):
        Settings(
            _env_file=None,
            app_env="production",
            database_url="postgresql+asyncpg://app:test@db.internal/app?ssl=require",
        )

    with pytest.raises(ValueError, match="PRODUCTION_REQUIRES_S3_BUCKET_OWNER"):
        Settings(
            _env_file=None,
            app_env="production",
            database_url="postgresql+asyncpg://app:test@db.internal/app?ssl=require",
            storage_backend="s3",
            s3_bucket="farmer-images",
        )
