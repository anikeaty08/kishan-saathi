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
