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
    bed_time: str | None = None
    wake_time: str | None = None
    sleep_duration_minutes: float | None = None
    time_in_bed_minutes: float | None = None
    sleep_efficiency: float | None = None
    sleep_latency_minutes: float | None = None
    night_awakenings: int | None = None
    resting_heart_rate: float | None = None
    mean_heart_rate: float | None = None
    hrv: float | None = None
    step_count: int | None = None
    activity_minutes: float | None = None
    daytime_sleepiness_score: int | None = None
    rls_symptom_score: int | None = None
    caffeine_evening: bool | None = None
    alcohol_evening: bool | None = None
    exercise: bool | None = None
    notes: str | None = None
    missing_mask_json: dict[str, bool]
