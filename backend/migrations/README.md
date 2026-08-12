# Database migrations

Every deployed schema change is represented by an ordered Alembic revision.

From the `backend` directory:

```powershell
uv run alembic upgrade head
uv run alembic downgrade -1
uv run alembic check
```

`DATABASE_URL` controls the migration target. Never run a downgrade against a
shared or deployed database without an explicit recovery plan and approval.
