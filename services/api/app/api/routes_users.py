from fastapi import APIRouter

from app.api.deps import CurrentUser, SessionDep
from app.db.models import UserProfile
from app.schemas.user import UserRead

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserRead)
def me(current_user: CurrentUser, session: SessionDep) -> UserRead:
    profile = session.get(UserProfile, current_user.id)
    return UserRead(
        id=current_user.id,
        email=current_user.email,
        created_at=current_user.created_at,
        age=profile.age if profile else None,
        sex=profile.sex if profile else None,
        height=profile.height if profile else None,
        weight=profile.weight if profile else None,
    )
