from fastapi.testclient import TestClient

from app.schemas.prediction import Tier1FeatureInput
from app.services.inference import predict_tier1
from app.services.model_registry import model_registry
from app.services.rls_experiments_adapter import RLSExperimentModelAdapter
from app.tests.conftest import register_and_auth


def test_login_supports_json_and_oauth_form(client: TestClient) -> None:
    response = client.post(
        "/auth/register",
        json={
            "email": "swagger-user@example.com",
            "password": "password123",
            "age": 51,
            "sex": "female",
            "height": 165,
            "weight": 62,
        },
    )
    assert response.status_code == 200, response.text

    json_login = client.post(
        "/auth/login",
        json={"email": "swagger-user@example.com", "password": "password123"},
    )
    assert json_login.status_code == 200, json_login.text
    assert json_login.json()["token_type"] == "bearer"

    form_login = client.post(
        "/auth/login",
        data={"username": "swagger-user@example.com", "password": "password123"},
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    assert form_login.status_code == 200, form_login.text
    token = form_login.json()["access_token"]
    me = client.get("/users/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200, me.text
    assert me.json()["email"] == "swagger-user@example.com"


def test_health(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_wearable_upload_and_daily_features(client: TestClient) -> None:
    headers = register_and_auth(client)
    response = client.post(
        "/wearable/upload",
        headers=headers,
        json={
            "events": [
                {
                    "source": "mock",
                    "data_type": "sleep",
                    "start_time": "2026-07-01T00:00:00Z",
                    "end_time": "2026-07-01T07:00:00Z",
                    "value_json": {"duration_minutes": 410, "sleep_efficiency": 82},
                },
                {
                    "source": "mock",
                    "data_type": "heart_rate",
                    "start_time": "2026-07-01T06:00:00Z",
                    "end_time": "2026-07-01T06:10:00Z",
                    "value_json": {"bpm": 74, "resting_bpm": 66},
                },
                {
                    "source": "mock",
                    "data_type": "steps",
                    "start_time": "2026-07-01T08:00:00Z",
                    "end_time": "2026-07-01T20:00:00Z",
                    "value_json": {"count": 6200},
                },
            ]
        },
    )
    assert response.status_code == 200, response.text
    assert response.json()["imported_events"] == 3
    features = client.get("/wearable/daily-features", headers=headers)
    assert features.status_code == 200
    assert features.json()[0]["sleep_duration_minutes"] == 410


def test_wearable_upload_updates_same_day_feature_for_latest_report(client: TestClient) -> None:
    headers = register_and_auth(client)
    empty_upload = client.post(
        "/wearable/upload",
        headers=headers,
        json={
            "events": [
                {
                    "source": "mock",
                    "data_type": "sleep",
                    "start_time": "2026-07-02T00:00:00Z",
                    "end_time": "2026-07-02T01:00:00Z",
                    "value_json": {},
                }
            ]
        },
    )
    assert empty_upload.status_code == 200, empty_upload.text

    valid_upload = client.post(
        "/wearable/upload",
        headers=headers,
        json={
            "events": [
                {
                    "source": "mock",
                    "data_type": "sleep",
                    "start_time": "2026-07-02T00:00:00Z",
                    "end_time": "2026-07-02T07:00:00Z",
                    "value_json": {"duration_minutes": 410, "sleep_efficiency": 82},
                },
                {
                    "source": "mock",
                    "data_type": "heart_rate",
                    "start_time": "2026-07-02T06:00:00Z",
                    "end_time": "2026-07-02T06:10:00Z",
                    "value_json": {"bpm": 74, "resting_bpm": 66},
                },
                {
                    "source": "mock",
                    "data_type": "steps",
                    "start_time": "2026-07-02T08:00:00Z",
                    "end_time": "2026-07-02T20:00:00Z",
                    "value_json": {"count": 6200},
                },
                {
                    "source": "mock",
                    "data_type": "activity",
                    "start_time": "2026-07-02T18:00:00Z",
                    "end_time": "2026-07-02T18:26:00Z",
                    "value_json": {"duration_minutes": 26},
                },
            ]
        },
    )
    assert valid_upload.status_code == 200, valid_upload.text
    report = client.get("/reports/latest", headers=headers)
    assert report.status_code == 200, report.text
    latest_features = report.json()["latest_daily_features"]
    assert latest_features["sleep_duration_minutes"] == 410
    assert latest_features["sleep_efficiency"] == 82
    assert latest_features["resting_heart_rate"] == 66
    assert latest_features["mean_heart_rate"] == 74
    assert latest_features["step_count"] == 6200
    assert latest_features["activity_minutes"] == 26


def test_latest_report_uses_newest_questionnaire_and_prediction(client: TestClient) -> None:
    headers = register_and_auth(client)
    first_questionnaire = {
        "urge_to_move_legs": 1,
        "worse_at_rest": 1,
        "relieved_by_movement": 1,
        "worse_in_evening_or_night": 1,
        "sleep_disturbance_score": 1,
        "symptom_frequency": 1,
        "symptom_severity": 1,
    }
    second_questionnaire = {
        "urge_to_move_legs": 4,
        "worse_at_rest": 4,
        "relieved_by_movement": 4,
        "worse_in_evening_or_night": 4,
        "sleep_disturbance_score": 10,
        "symptom_frequency": 7,
        "symptom_severity": 10,
    }
    assert client.post("/questionnaire/submit", headers=headers, json=first_questionnaire).status_code == 200
    assert client.post("/questionnaire/submit", headers=headers, json=second_questionnaire).status_code == 200

    low_prediction = {
        "sleep_duration_minutes": 450,
        "sleep_efficiency": 90,
        "resting_heart_rate": 60,
        "mean_heart_rate": 65,
        "step_count": 9000,
        "activity_minutes": 45,
        "age": 35,
        "sex": "female",
    }
    high_prediction = {
        **low_prediction,
        "urge_to_move_legs": 4,
        "worse_at_rest": 4,
        "relieved_by_movement": 4,
        "worse_in_evening_or_night": 4,
        "sleep_disturbance_score": 10,
        "symptom_frequency": 7,
        "symptom_severity": 10,
    }
    assert client.post("/predict/tier1", headers=headers, json=low_prediction).status_code == 200
    assert client.post("/predict/tier2", headers=headers, json=high_prediction).status_code == 200

    report = client.get("/reports/latest", headers=headers)
    assert report.status_code == 200, report.text
    body = report.json()
    assert body["latest_questionnaire"]["response_json"]["urge_to_move_legs"] == 4
    assert body["latest_prediction"]["tier"] == "tier2"
    assert body["latest_prediction"]["risk_level"] == "high"


def test_questionnaire_submission(client: TestClient) -> None:
    headers = register_and_auth(client)
    payload = {
        "urge_to_move_legs": 3,
        "worse_at_rest": 3,
        "relieved_by_movement": 2,
        "worse_in_evening_or_night": 3,
        "sleep_disturbance_score": 6,
        "symptom_frequency": 4,
        "symptom_severity": 5,
    }
    response = client.post("/questionnaire/submit", headers=headers, json=payload)
    assert response.status_code == 200, response.text
    history = client.get("/questionnaire/history", headers=headers)
    assert len(history.json()) == 1


def test_prediction_endpoint_returns_valid_score(client: TestClient) -> None:
    headers = register_and_auth(client)
    response = client.post(
        "/predict/tier1",
        headers=headers,
        json={
            "sleep_duration_minutes": 390,
            "sleep_efficiency": 78,
            "resting_heart_rate": 72,
            "mean_heart_rate": 82,
            "step_count": 4200,
            "activity_minutes": 18,
            "age": 56,
            "sex": "female",
            "missing_mask_json": {},
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert 0 <= body["risk_score"] <= 1
    assert body["risk_level"] in {"low", "moderate", "high"}
    assert "model_version" in body
    assert "non-diagnostic" in body["disclaimer_text"]


def test_fallback_model_is_deterministic() -> None:
    payload = Tier1FeatureInput(
        sleep_duration_minutes=390,
        sleep_efficiency=78,
        resting_heart_rate=72,
        mean_heart_rate=82,
        step_count=4200,
        activity_minutes=18,
        age=56,
        sex="female",
    )
    first = predict_tier1(payload)
    second = predict_tier1(payload)
    assert first.risk_score == second.risk_score
    assert first.model_version == second.model_version


def test_experiment_adapter_projects_mvp_features() -> None:
    adapter = RLSExperimentModelAdapter(model_registry.artifact_dir / "rls_experiments" / "sleep_heart_basic_q__apple")
    projected = adapter.to_experiment_features(
        {
            "sleep_duration_minutes": 405,
            "sleep_efficiency": 80,
            "mean_heart_rate": 78,
            "resting_heart_rate": 69,
            "age": 51,
            "sex": "female",
            "height": 165,
            "weight": 62,
            "family_history_rls": True,
            "diabetes": False,
            "psychiatric_medication": False,
            "non_leg_symptoms": None,
        }
    )
    assert projected["总睡眠时间/分"] == 405
    assert projected["睡眠效率%"] == 80
    assert projected["平均心率"] == 78
    assert projected["平均-最慢心率差值"] == 9
    assert projected["性别_男1女0"] == 0
    assert round(projected["BMI"], 2) == 22.77
    assert projected["家系（口述或诊断确认家族内有患病）"] == 1


def test_real_adapter_falls_back_without_optional_dependencies() -> None:
    payload = Tier1FeatureInput(
        sleep_duration_minutes=390,
        sleep_efficiency=78,
        resting_heart_rate=72,
        mean_heart_rate=82,
        step_count=4200,
        activity_minutes=18,
        age=56,
        sex="female",
    )
    response = predict_tier1(payload)
    assert 0 <= response.risk_score <= 1
    assert response.model_version.startswith("tier1-fallback") or "xgb-tabm" in response.model_version
