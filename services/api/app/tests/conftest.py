import os
from uuid import uuid4
from collections.abc import Generator

os.environ["DATABASE_URL"] = "sqlite:///:memory:"
os.environ["SECRET_KEY"] = "test-secret"

from fastapi.testclient import TestClient
import pytest
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

import app.db.session as db_session
from app.api import deps
from app.main import app


engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
db_session.engine = engine


def override_get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session


app.dependency_overrides[deps.get_session] = override_get_session
app.dependency_overrides[db_session.get_session] = override_get_session


def fresh_db() -> None:
    SQLModel.metadata.drop_all(engine)
    SQLModel.metadata.create_all(engine)


def register_and_auth(client: TestClient) -> dict[str, str]:
    email = f"test-{uuid4().hex}@example.com"
    response = client.post(
        "/auth/register",
        json={
            "email": email,
            "password": "password123",
            "age": 51,
            "sex": "female",
            "height": 165,
            "weight": 62,
        },
    )
    assert response.status_code == 200, response.text
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
    fresh_db()
    with TestClient(app) as test_client:
        yield test_client
