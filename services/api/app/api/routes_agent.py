from fastapi import APIRouter

from app.api.deps import CurrentUser, SessionDep
from app.core.config import get_settings
from app.schemas.agent import AgentFeedbackRequest, AgentFeedbackResponse, SleepAgentRequest, SleepAgentResponse
from app.services.user_memory import memory_to_read, record_feedback
from app.services.sleep_agent import build_sleep_agent_response

router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/sleep", response_model=SleepAgentResponse)
def sleep_agent(payload: SleepAgentRequest, session: SessionDep, current_user: CurrentUser) -> SleepAgentResponse:
    return build_sleep_agent_response(session, current_user, payload, get_settings())


@router.post("/feedback", response_model=AgentFeedbackResponse)
def agent_feedback(payload: AgentFeedbackRequest, session: SessionDep, current_user: CurrentUser) -> AgentFeedbackResponse:
    memory = record_feedback(session, current_user.id, payload)
    return AgentFeedbackResponse(status="recorded", memory=memory_to_read(memory))
