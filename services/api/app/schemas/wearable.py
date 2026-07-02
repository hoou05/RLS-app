from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, Field


class WearableEventIn(BaseModel):
    source: str = "mock"
    data_type: str = Field(pattern="^(sleep|heart_rate|steps|activity)$")
    start_time: datetime
    end_time: datetime
    value_json: dict[str, Any]


class WearableUploadRequest(BaseModel):
    events: list[WearableEventIn]


class WearableUploadResponse(BaseModel):
    imported_events: int
    generated_daily_features: int


class DailyFeatureRead(BaseModel):
    date: date
    sleep_duration_minutes: float | None = None
    sleep_efficiency: float | None = None
    resting_heart_rate: float | None = None
    mean_heart_rate: float | None = None
    step_count: int | None = None
    activity_minutes: float | None = None
    missing_mask_json: dict[str, bool]
