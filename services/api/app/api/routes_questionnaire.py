from fastapi import APIRouter
from sqlmodel import select

from app.api.deps import CurrentUser, SessionDep
from app.db.models import AuditLog, QuestionnaireResponse
from app.schemas.questionnaire import QuestionnaireRead, QuestionnaireSubmitRequest

router = APIRouter(prefix="/questionnaire", tags=["questionnaire"])


@router.post("/submit", response_model=QuestionnaireRead)
def submit(payload: QuestionnaireSubmitRequest, current_user: CurrentUser, session: SessionDep) -> QuestionnaireResponse:
    response = QuestionnaireResponse(
        user_id=current_user.id,
        questionnaire_type=payload.questionnaire_type,
        response_json=payload.model_dump(exclude={"questionnaire_type"}),
    )
    session.add(response)
    session.add(AuditLog(user_id=current_user.id, action="questionnaire.submit", metadata_json={"type": payload.questionnaire_type}))
    session.commit()
    session.refresh(response)
    return response


@router.get("/history", response_model=list[QuestionnaireRead])
def history(current_user: CurrentUser, session: SessionDep) -> list[QuestionnaireResponse]:
    statement = (
        select(QuestionnaireResponse)
        .where(QuestionnaireResponse.user_id == current_user.id)
        .order_by(QuestionnaireResponse.submitted_at.desc(), QuestionnaireResponse.id.desc())
    )
    return list(session.exec(statement).all())
