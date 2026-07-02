from datetime import date as dt_date, datetime, timezone
from typing import Any

from sqlalchemy import Column
from sqlalchemy.types import JSON
from sqlmodel import Field, SQLModel


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    email: str = Field(index=True, unique=True)
    hashed_password: str
    created_at: datetime = Field(default_factory=utcnow)


class UserProfile(SQLModel, table=True):
    user_id: int = Field(foreign_key="user.id", primary_key=True)
    age: int | None = None
    sex: str | None = None
    height: float | None = None
    weight: float | None = None


class Consent(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    consent_version: str
    accepted_at: datetime = Field(default_factory=utcnow)


class WearableRawData(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    source: str
    data_type: str
    start_time: datetime
    end_time: datetime
    value_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    created_at: datetime = Field(default_factory=utcnow)


class DailyFeature(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    date: dt_date = Field(index=True)
    sleep_duration_minutes: float | None = None
    sleep_efficiency: float | None = None
    resting_heart_rate: float | None = None
    mean_heart_rate: float | None = None
    step_count: int | None = None
    activity_minutes: float | None = None
    missing_mask_json: dict[str, bool] = Field(default_factory=dict, sa_column=Column(JSON))
    created_at: datetime = Field(default_factory=utcnow)


class QuestionnaireResponse(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    questionnaire_type: str
    response_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    submitted_at: datetime = Field(default_factory=utcnow)


class PredictionResult(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    tier: str
    model_version: str
    risk_score: float
    risk_level: str
    explanation_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    recommendation_text: str
    created_at: datetime = Field(default_factory=utcnow)


class AuditLog(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int | None = Field(default=None, foreign_key="user.id", index=True)
    action: str
    metadata_json: dict[str, Any] = Field(default_factory=dict, sa_column=Column(JSON))
    created_at: datetime = Field(default_factory=utcnow)
