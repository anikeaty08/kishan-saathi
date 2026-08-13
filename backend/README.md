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
  weather, location-search, history, activity-photo, and report APIs under
  `/api/v1`.

`POST /api/v1/diagnoses/{case_id}/progression` compares the latest two stored
retake batches by default, or two explicitly selected assessment IDs. It uses
OpenAI image input only to estimate visible symptom change (`improving`,
`worsening`, `unchanged`, or `unclear`). It does not receive or produce disease
labels and cannot replace the trained classifier. Owner checks, image-quality
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

Important current limitation: the leaf inference plugin fails with the explicit
`LEAF_MODEL_NOT_CONFIGURED` code until the evaluated model artifact or service
is supplied. Specific chemical treatment instructions are intentionally blocked
without an approved authoritative source.
