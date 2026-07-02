from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    age: int | None = Field(default=None, ge=0, le=120)
    sex: str | None = None
    height: float | None = Field(default=None, gt=0)
    weight: float | None = Field(default=None, gt=0)
    consent_version: str = "mvp-consent-v1"


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserRead(BaseModel):
    id: int
    email: EmailStr
    created_at: datetime
    age: int | None = None
    sex: str | None = None
    height: float | None = None
    weight: float | None = None
