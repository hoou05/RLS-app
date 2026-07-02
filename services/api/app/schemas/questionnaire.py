from datetime import datetime

from pydantic import BaseModel, Field


class QuestionnaireSubmitRequest(BaseModel):
    questionnaire_type: str = "rls_screening_v1"
    urge_to_move_legs: int = Field(ge=0, le=4)
    worse_at_rest: int = Field(ge=0, le=4)
    relieved_by_movement: int = Field(ge=0, le=4)
    worse_in_evening_or_night: int = Field(ge=0, le=4)
    sleep_disturbance_score: int = Field(ge=0, le=10)
    symptom_frequency: int = Field(ge=0, le=7)
    symptom_severity: int = Field(ge=0, le=10)


class QuestionnaireRead(BaseModel):
    id: int
    questionnaire_type: str
    response_json: dict
    submitted_at: datetime
