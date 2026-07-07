from datetime import datetime

from pydantic import BaseModel, Field

DISCLAIMER_TEXT = (
    "This is a non-diagnostic screening risk estimate. It does not determine whether "
    "you have RLS. Consult a clinician if symptoms persist or concern you."
)


class Tier1FeatureInput(BaseModel):
    sleep_duration_minutes: float | None = Field(default=None, ge=0)
    sleep_efficiency: float | None = Field(default=None, ge=0, le=100)
    waso_minutes: float | None = Field(default=None, ge=0)
    sleep_latency_minutes: float | None = Field(default=None, ge=0)
    rem_latency_minutes: float | None = Field(default=None, ge=0)
    awake_stage_minutes: float | None = Field(default=None, ge=0)
    average_spo2: float | None = Field(default=None, ge=0, le=100)
    minimum_spo2: float | None = Field(default=None, ge=0, le=100)
    light_sleep_minutes: float | None = Field(default=None, ge=0)
    light_sleep_percent: float | None = Field(default=None, ge=0, le=100)
    deep_sleep_minutes: float | None = Field(default=None, ge=0)
    deep_sleep_percent: float | None = Field(default=None, ge=0, le=100)
    rem_sleep_minutes: float | None = Field(default=None, ge=0)
    rem_sleep_percent: float | None = Field(default=None, ge=0, le=100)
    resting_heart_rate: float | None = Field(default=None, ge=20, le=220)
    mean_heart_rate: float | None = Field(default=None, ge=20, le=220)
    step_count: int | None = Field(default=None, ge=0)
    activity_minutes: float | None = Field(default=None, ge=0)
    age: int | None = Field(default=None, ge=0, le=120)
    sex: str | None = None
    height: float | None = Field(default=None, gt=0)
    weight: float | None = Field(default=None, gt=0)
    min_heart_rate: float | None = Field(default=None, ge=20, le=220)
    max_heart_rate: float | None = Field(default=None, ge=20, le=220)
    experiment_features: dict[str, float | int | None] = Field(default_factory=dict)
    missing_mask_json: dict[str, bool] = Field(default_factory=dict)


class Tier2FeatureInput(Tier1FeatureInput):
    urge_to_move_legs: int | None = Field(default=None, ge=0, le=4)
    worse_at_rest: int | None = Field(default=None, ge=0, le=4)
    relieved_by_movement: int | None = Field(default=None, ge=0, le=4)
    worse_in_evening_or_night: int | None = Field(default=None, ge=0, le=4)
    sleep_disturbance_score: int | None = Field(default=None, ge=0, le=10)
    symptom_frequency: int | None = Field(default=None, ge=0, le=7)
    symptom_severity: int | None = Field(default=None, ge=0, le=10)
    family_history_rls: bool | None = None
    diabetes: bool | None = None
    psychiatric_medication: bool | None = None
    non_leg_symptoms: bool | None = None


class PredictionResponse(BaseModel):
    risk_score: float
    risk_level: str
    model_version: str
    explanation_json: dict
    recommendation_text: str
    disclaimer_text: str = DISCLAIMER_TEXT


class PredictionHistoryRead(PredictionResponse):
    id: int
    tier: str
    created_at: datetime
