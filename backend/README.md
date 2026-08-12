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

The API currently exposes:

- `GET /health/live` for process liveness without dependency calls.
- `GET /health/ready` for PostgreSQL readiness using a bounded `SELECT 1`.
- `GET /docs` for the generated OpenAPI interface.

Run checks with:

```powershell
uv run ruff check app tests
uv run mypy app
uv run pytest
```

Authentication and farmer-profile behavior are intentionally the next vertical
slice; this foundation does not pretend those features already exist.
