from fastapi import APIRouter, HTTPException, Request, status
from pydantic import ValidationError
from sqlmodel import select

from app.api.deps import SessionDep
from app.core.security import create_access_token, hash_password, verify_password
from app.db.models import AuditLog, Consent, User, UserProfile
from app.schemas.user import Token, UserLogin, UserRegister

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=Token)
def register(payload: UserRegister, session: SessionDep) -> Token:
    existing = session.exec(select(User).where(User.email == payload.email)).first()
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")
    user = User(email=str(payload.email), hashed_password=hash_password(payload.password))
    session.add(user)
    session.commit()
    session.refresh(user)
    session.add(UserProfile(user_id=user.id, age=payload.age, sex=payload.sex, height=payload.height, weight=payload.weight))
    session.add(Consent(user_id=user.id, consent_version=payload.consent_version))
    session.add(AuditLog(user_id=user.id, action="auth.register", metadata_json={"consent_version": payload.consent_version}))
    session.commit()
    return Token(access_token=create_access_token(str(user.id)))


@router.post("/login", response_model=Token)
async def login(request: Request, session: SessionDep) -> Token:
    payload = await _parse_login_payload(request)
    return _login_with_credentials(payload.email, payload.password, session)


async def _parse_login_payload(request: Request) -> UserLogin:
    content_type = request.headers.get("content-type", "")
    if "application/x-www-form-urlencoded" in content_type or "multipart/form-data" in content_type:
        form = await request.form()
        data = {
            "email": form.get("username") or form.get("email"),
            "password": form.get("password"),
        }
    else:
        data = await request.json()
    try:
        return UserLogin.model_validate(data)
    except ValidationError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=exc.errors()) from exc


def _login_with_credentials(email: str, password: str, session: SessionDep) -> Token:
    user = session.exec(select(User).where(User.email == email)).first()
    if user is None or not verify_password(password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password")
    session.add(AuditLog(user_id=user.id, action="auth.login", metadata_json={}))
    session.commit()
    return Token(access_token=create_access_token(str(user.id)))
