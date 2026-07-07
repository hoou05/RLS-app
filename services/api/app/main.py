from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import routes_agent, routes_auth, routes_questionnaire, routes_reports, routes_users, routes_wearable
from app.api.routes_prediction import history_router, router as prediction_router
from app.core.config import get_settings
from app.db.session import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


settings = get_settings()
app = FastAPI(title=settings.app_name, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "rls-screening-api"}


app.include_router(routes_auth.router)
app.include_router(routes_users.router)
app.include_router(routes_wearable.router)
app.include_router(routes_questionnaire.router)
app.include_router(prediction_router)
app.include_router(history_router)
app.include_router(routes_reports.router)
app.include_router(routes_agent.router)
