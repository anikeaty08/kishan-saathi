# KrishiSathi Backend

Raw architecture scaffold for the FastAPI backend. Implementation begins with
the foundation, health, authentication, and farmer-profile vertical slice.

Module boundaries:

- `api`: top-level API composition and versioning.
- `core`: configuration, dependency wiring, errors, logging, and security.
- `database`: SQLAlchemy session and declarative model foundation.
- `integrations`: replaceable provider/plugin contracts and adapters.
- `modules`: self-contained product features.
- `migrations`: Alembic database migrations.
- `tests`: unit, integration, and API contract tests.

The scaffold intentionally contains no implemented endpoints or provider calls.
