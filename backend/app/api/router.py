"""Top-level API router composition."""

from fastapi import APIRouter

from app.modules.chats.router import router as chats_router
from app.modules.diagnoses.router import router as diagnoses_router
from app.modules.farms.router import router as farms_router
from app.modules.health.router import router as health_router
from app.modules.history.router import router as history_router
from app.modules.locations.router import router as locations_router
from app.modules.memories.router import router as memories_router
from app.modules.reminders.router import router as reminders_router
from app.modules.reports.router import router as reports_router
from app.modules.storage_cleanup.router import router as storage_cleanup_router
from app.modules.users.router import router as users_router
from app.modules.voice.router import router as voice_router
from app.modules.weather.router import router as weather_router

api_router = APIRouter()
api_router.include_router(health_router)

versioned_api_router = APIRouter()
versioned_api_router.include_router(users_router)
versioned_api_router.include_router(farms_router)
versioned_api_router.include_router(diagnoses_router)
versioned_api_router.include_router(history_router)
versioned_api_router.include_router(chats_router)
versioned_api_router.include_router(memories_router)
versioned_api_router.include_router(locations_router)
versioned_api_router.include_router(reminders_router)
versioned_api_router.include_router(reports_router)
versioned_api_router.include_router(storage_cleanup_router)
versioned_api_router.include_router(weather_router)
versioned_api_router.include_router(voice_router)
