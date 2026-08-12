"""Top-level API router composition."""

from fastapi import APIRouter

from app.modules.health.router import router as health_router
from app.modules.users.router import router as users_router

api_router = APIRouter()
api_router.include_router(health_router)

versioned_api_router = APIRouter()
versioned_api_router.include_router(users_router)
