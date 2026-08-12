# kishan-saathi

Backend foundation for the Kishan Saathi farmer assistance application.

## Backend environment

The backend uses Python 3.12 and `uv` for dependency and virtual-environment
management.

```powershell
cd backend
uv sync --group dev
```

Copy `backend/.env.example` to `backend/.env` before local development and keep
all credentials out of Git. The application modules are currently structural
stubs; the runnable FastAPI vertical slice will be implemented next.
