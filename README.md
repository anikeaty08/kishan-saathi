# kishan-saathi

Production-oriented modular FastAPI backend for the Kishan Saathi farmer
assistance application.

## Backend environment

The backend uses Python 3.12 and `uv` for dependency and virtual-environment
management.

```powershell
cd backend
uv sync --group dev
```

Copy `backend/.env.example` to `backend/.env` before local development and keep
all credentials out of Git.

Implemented backend modules include Cognito-authenticated farmer profiles,
farms/plots/crop cycles, private multi-image diagnosis records, scoped AI chats,
Mem0-indexed canonical memory, reminders, weather/geocoding, timelines, activity
photos, approved diagnosis reports, and durable object cleanup.

The real leaf-classification provider remains intentionally unavailable until
the evaluated checkpoint/class manifest and serving contract are supplied.
Exact chemical ingredient, dosage, frequency, and application instructions are
also disabled until an approved authoritative treatment source is configured.

Run validation:

```powershell
cd backend
uv run ruff check app tests
uv run mypy app tests
uv run pytest
uv run alembic upgrade head --sql
```
