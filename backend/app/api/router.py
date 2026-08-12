"""Top-level API router composition."""

from fastapi import APIRouter

from app.modules.chats.router import router as chats_router
from app.modules.diagnoses.router import router as diagnoses_router
from app.modules.farms.router import router as farms_router
from app.modules.health.router import router as health_router
from app.modules.reminders.router import router as reminders_router
from app.modules.users.router import router as users_router
from app.modules.weather.router import router as weather_router

api_router = APIRouter()
api_router.include_router(health_router)

versioned_api_router = APIRouter()
versioned_api_router.include_router(users_router)
versioned_api_router.include_router(farms_router)
versioned_api_router.include_router(diagnoses_router)
versioned_api_router.include_router(chats_router)
versioned_api_router.include_router(reminders_router)
versioned_api_router.include_router(weather_router)
