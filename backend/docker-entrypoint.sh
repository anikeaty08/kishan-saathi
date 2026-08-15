#!/bin/sh
set -eu

if [ "${RUN_MIGRATIONS_ON_START:-0}" = "1" ]; then
  uv run --no-sync alembic upgrade head
fi

exec uv run --no-sync uvicorn app.main:app \
  --host 0.0.0.0 \
  --port "${PORT:-8000}" \
  --no-access-log
