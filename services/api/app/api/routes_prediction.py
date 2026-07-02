from fastapi import APIRouter
from sqlmodel import select

from app.api.deps import CurrentUser, SessionDep
from app.db.models import AuditLog, PredictionResult
from app.schemas.prediction import PredictionHistoryRead, PredictionResponse, Tier1FeatureInput, Tier2FeatureInput
from app.services.inference import predict_tier1, predict_tier2

router = APIRouter(prefix="/predict", tags=["prediction"])
history_router = APIRouter(prefix="/predictions", tags=["prediction"])


def _save_prediction(session: SessionDep, user_id: int, tier: str, response: PredictionResponse) -> None:
    session.add(
        PredictionResult(
            user_id=user_id,
            tier=tier,
            model_version=response.model_version,
            risk_score=response.risk_score,
            risk_level=response.risk_level,
            explanation_json=response.explanation_json,
            recommendation_text=response.recommendation_text,
        )
    )
    session.add(AuditLog(user_id=user_id, action=f"predict.{tier}", metadata_json={"model_version": response.model_version}))
    session.commit()


@router.post("/tier1", response_model=PredictionResponse)
def tier1(payload: Tier1FeatureInput, current_user: CurrentUser, session: SessionDep) -> PredictionResponse:
    response = predict_tier1(payload)
    _save_prediction(session, current_user.id, "tier1", response)
    return response


@router.post("/tier2", response_model=PredictionResponse)
def tier2(payload: Tier2FeatureInput, current_user: CurrentUser, session: SessionDep) -> PredictionResponse:
    response = predict_tier2(payload)
    _save_prediction(session, current_user.id, "tier2", response)
    return response


@history_router.get("/history", response_model=list[PredictionHistoryRead])
def history(current_user: CurrentUser, session: SessionDep) -> list[PredictionResult]:
    statement = (
        select(PredictionResult)
        .where(PredictionResult.user_id == current_user.id)
        .order_by(PredictionResult.created_at.desc(), PredictionResult.id.desc())
    )
    return list(session.exec(statement).all())
