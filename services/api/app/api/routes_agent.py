from fastapi import APIRouter

from app.api.deps import CurrentUser, SessionDep
from app.core.config import get_settings
from app.schemas.agent import SleepAgentRequest, SleepAgentResponse
from app.services.sleep_agent import build_sleep_agent_response

router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/sleep", response_model=SleepAgentResponse)
def sleep_agent(payload: SleepAgentRequest, session: SessionDep, current_user: CurrentUser) -> SleepAgentResponse:
    return build_sleep_agent_response(session, current_user, payload, get_settings())
