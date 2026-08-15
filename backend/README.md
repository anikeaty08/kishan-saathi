# Kishan Saathi Backend

Runnable FastAPI foundation for the Kishan Saathi farmer-assistance backend.

Module boundaries:

- `api`: top-level API composition and versioning.
- `core`: configuration, dependency wiring, errors, logging, and security.
- `database`: SQLAlchemy session and declarative model foundation.
- `integrations`: replaceable provider/plugin contracts and adapters.
- `modules`: self-contained product features.
- `migrations`: Alembic database migrations.
- `tests`: unit, integration, and API contract tests.

## Local setup

```powershell
uv sync --group dev
Copy-Item .env.example .env
docker compose up -d postgres
uv run uvicorn app.main:app --reload
```

The API exposes:

- `GET /health/live` for process liveness without dependency calls.
- `GET /health/ready` for PostgreSQL readiness using a bounded `SELECT 1`.
- `GET /docs` for the generated OpenAPI interface.
- Authenticated farm, plot, crop-cycle, diagnosis, chat, memory, reminder,
  weather, location-search, history, activity-photo, voice, and report APIs under
  `/api/v1`.

Saathi voice uses bounded request-based audio. The mobile app records a temporary
message, the authenticated backend transcribes it, and the farmer reviews the
transcript before sending it through the normal durable chat queue. Typed and
spoken questions therefore use the same owner-scoped history, farm/plot/scan
context, memory, tools, and safety validation. Read-aloud is generated only from
an existing owned assistant message; arbitrary client-authored text cannot use the
speech endpoint. Recordings and synthesized speech are not persisted by the backend.

`POST /api/v1/diagnoses/{case_id}/progression` compares the latest two stored
retake batches by default, or two explicitly selected assessment IDs. It uses
OpenAI image input only to estimate visible symptom change (`improving`,
`worsening`, `unchanged`, or `unclear`). It does not receive or produce disease
labels. It may read the backend classifier result as immutable context, but it
cannot alter or replace that result. Owner checks, image-quality
gates, bounded image counts/bytes, typed output validation, and `store=false`
are enforced before a response is returned.

Chat sends use durable ordered turns. `POST /api/v1/chats/{chat_id}/messages`
returns `202` with a queued turn, while the background worker processes only
the earliest turn in each chat. Different chats can run concurrently. Clients
poll `GET /api/v1/chats/{chat_id}/turns/{turn_id}` and may explicitly retry a
terminal failed turn with `POST .../{turn_id}/retry`; the same idempotency key
never creates a duplicate farmer message or paid LLM call. Assistant content is
stored both as natural farmer-facing text and as the validated structured reply
used by the mobile UI.

Run checks with:

```powershell
uv run ruff check app tests
uv run mypy app
uv run pytest
```

Leaf inference is selected through `LEAF_INFERENCE_BACKEND`. The temporary
`openai_vision` plugin keeps output inside the immutable 89-class PlantWild
manifest, preserves per-image evidence, uses `store=false`, and caps confidence
below the application's high-confidence threshold because it has not been
calibrated on the held-out test set. Set the backend to `disabled` to return
`LEAF_MODEL_NOT_CONFIGURED`. The evaluated DINOv2/ConvNeXt adapter will replace
this plugin without changing the diagnosis API or lifecycle. Specific chemical
treatment instructions are intentionally blocked without an approved
authoritative source.

## Private image storage

Development and Docker testing use `STORAGE_BACKEND=local`. Production fails
closed unless `STORAGE_BACKEND=s3`, `S3_BUCKET`, and the 12-digit
`S3_EXPECTED_BUCKET_OWNER` are configured. The API uses its AWS workload role;
static AWS access keys do not belong in `.env`.

The S3 adapter:

- creates opaque keys beneath `S3_KEY_PREFIX/<farmer-id>/<category>/` and checks
  that owner prefix on every read and delete;
- never creates a public URL or object ACL;
- requests SHA-256 checksums, `private, no-store`, and server-side encryption;
- supports SSE-S3 by default or SSE-KMS when `S3_KMS_KEY_ID` is supplied;
- uses `ExpectedBucketOwner` to prevent accidental cross-account bucket access;
- preserves the durable deletion-job workflow for scans, activity photos, and
  copied report images.

The bucket must have all S3 Block Public Access options enabled, Object Ownership
set to Bucket owner enforced (ACLs disabled), TLS-only access, and a least-privilege
workload-role policy limited to `GetObject`, `PutObject`, and `DeleteObject` under
the configured prefix. Do not enable bucket versioning without extending privacy
deletion to remove historical object versions.
