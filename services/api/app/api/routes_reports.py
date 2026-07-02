from fastapi import APIRouter
from sqlmodel import select

from app.api.deps import CurrentUser, SessionDep
from app.db.models import DailyFeature, PredictionResult, QuestionnaireResponse

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/latest")
def latest_report(current_user: CurrentUser, session: SessionDep) -> dict:
    latest_prediction = session.exec(
        select(PredictionResult)
        .where(PredictionResult.user_id == current_user.id)
        .order_by(PredictionResult.created_at.desc(), PredictionResult.id.desc())
    ).first()
    latest_features = session.exec(
        select(DailyFeature)
        .where(DailyFeature.user_id == current_user.id)
        .order_by(DailyFeature.date.desc(), DailyFeature.created_at.desc(), DailyFeature.id.desc())
    ).first()
    latest_questionnaire = session.exec(
        select(QuestionnaireResponse)
        .where(QuestionnaireResponse.user_id == current_user.id)
        .order_by(QuestionnaireResponse.submitted_at.desc(), QuestionnaireResponse.id.desc())
    ).first()
    return {
        "latest_prediction": latest_prediction,
        "latest_daily_features": latest_features,
        "latest_questionnaire": latest_questionnaire,
        "screening_disclaimer": "This report is a non-diagnostic screening summary and should not be used as a clinical diagnosis.",
    }
