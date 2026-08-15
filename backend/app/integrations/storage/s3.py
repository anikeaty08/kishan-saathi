"""Private AWS S3 object storage with owner-bound opaque keys."""

import asyncio
from collections.abc import Mapping
from typing import Any
from uuid import UUID, uuid4

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from mypy_boto3_s3 import S3Client

from app.core.config import Settings
from app.core.errors import ApplicationError
from app.integrations.storage.provider import ObjectStorageProvider, StoredObject


class S3ObjectStorage(ObjectStorageProvider):
    """Keep farmer images private and accessible only through authenticated APIs."""

    def __init__(self, settings: Settings, *, client: S3Client | None = None) -> None:
        self._bucket = settings.s3_bucket
        self._prefix = settings.s3_key_prefix.strip("/")
        self._kms_key_id = settings.s3_kms_key_id or None
        self._expected_owner = settings.s3_expected_bucket_owner or None
        self._max_object_bytes = settings.max_image_bytes
        self._client = client or boto3.client(
            "s3",
            region_name=settings.aws_region,
            endpoint_url=settings.s3_endpoint_url or None,
            config=Config(
                connect_timeout=settings.external_request_timeout_seconds,
                read_timeout=settings.external_request_timeout_seconds,
                retries={"max_attempts": 3, "mode": "standard"},
            ),
        )

    async def put_private_image(
        self,
        *,
        owner_id: UUID,
        category: str,
        content: bytes,
    ) -> StoredObject:
        safe_category = self._safe_segment(category)
        key = f"{self._prefix}/{owner_id}/{safe_category}/{uuid4()}.jpg"
        parameters: dict[str, Any] = {
            "Bucket": self._bucket,
            "Key": key,
            "Body": content,
            "ContentType": "image/jpeg",
            "CacheControl": "private, no-store",
            "ChecksumAlgorithm": "SHA256",
            "Metadata": {"owner-id": str(owner_id)},
            **self._owner_parameter(),
        }
        if self._kms_key_id is None:
            parameters["ServerSideEncryption"] = "AES256"
        else:
            parameters.update(
                ServerSideEncryption="aws:kms",
                SSEKMSKeyId=self._kms_key_id,
                BucketKeyEnabled=True,
            )
        try:
            await asyncio.to_thread(lambda: self._client.put_object(**parameters))
        except (BotoCoreError, ClientError) as exc:
            raise ApplicationError(code="STORAGE_WRITE_FAILED", status_code=503) from exc
        return StoredObject(key=key, size_bytes=len(content), media_type="image/jpeg")

    async def read_private(self, *, owner_id: UUID, key: str) -> bytes:
        self._validate_owned_key(owner_id, key)
        response: Mapping[str, Any]
        expected_owner = self._expected_owner
        try:
            if expected_owner is None:
                response = await asyncio.to_thread(
                    lambda: self._client.get_object(Bucket=self._bucket, Key=key)
                )
            else:
                response = await asyncio.to_thread(
                    lambda: self._client.get_object(
                        Bucket=self._bucket,
                        Key=key,
                        ExpectedBucketOwner=expected_owner,
                    )
                )
            content_length = response.get("ContentLength")
            if isinstance(content_length, int) and content_length > self._max_object_bytes:
                raise ApplicationError(code="STORAGE_OBJECT_TOO_LARGE", status_code=422)
            body = response["Body"]
            try:
                content = await asyncio.to_thread(body.read, self._max_object_bytes + 1)
            finally:
                body.close()
        except ClientError as exc:
            error_code = str(exc.response.get("Error", {}).get("Code", ""))
            if error_code in {"NoSuchKey", "404", "NotFound"}:
                raise ApplicationError(code="STORAGE_OBJECT_NOT_FOUND", status_code=404) from exc
            raise ApplicationError(code="STORAGE_READ_FAILED", status_code=503) from exc
        except (BotoCoreError, KeyError, TypeError) as exc:
            raise ApplicationError(code="STORAGE_READ_FAILED", status_code=503) from exc
        if not isinstance(content, bytes):
            raise ApplicationError(code="STORAGE_READ_FAILED", status_code=503)
        if len(content) > self._max_object_bytes:
            raise ApplicationError(code="STORAGE_OBJECT_TOO_LARGE", status_code=422)
        return content

    async def delete_private(self, *, owner_id: UUID, key: str) -> None:
        self._validate_owned_key(owner_id, key)
        expected_owner = self._expected_owner
        try:
            if expected_owner is None:
                await asyncio.to_thread(
                    lambda: self._client.delete_object(Bucket=self._bucket, Key=key)
                )
            else:
                await asyncio.to_thread(
                    lambda: self._client.delete_object(
                        Bucket=self._bucket,
                        Key=key,
                        ExpectedBucketOwner=expected_owner,
                    )
                )
        except (BotoCoreError, ClientError) as exc:
            raise ApplicationError(code="STORAGE_DELETE_FAILED", status_code=503) from exc

    async def close(self) -> None:
        await asyncio.to_thread(self._client.close)

    def _owner_parameter(self) -> dict[str, str]:
        if self._expected_owner is None:
            return {}
        return {"ExpectedBucketOwner": self._expected_owner}

    def _validate_owned_key(self, owner_id: UUID, key: str) -> None:
        expected_prefix = f"{self._prefix}/{owner_id}/"
        if not key.startswith(expected_prefix) or ".." in key.split("/"):
            raise ApplicationError(code="STORAGE_OBJECT_NOT_FOUND", status_code=404)

    @staticmethod
    def _safe_segment(value: str) -> str:
        if not value or not value.replace("-", "").replace("_", "").isalnum():
            raise ApplicationError(code="STORAGE_CATEGORY_INVALID", status_code=422)
        return value
