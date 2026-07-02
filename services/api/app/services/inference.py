from math import exp
from typing import Any

from app.schemas.prediction import PredictionResponse, Tier1FeatureInput, Tier2FeatureInput
from app.services.model_registry import model_registry
from app.services.rls_experiments_adapter import ModelAdapterUnavailable
from app.services.risk_interpretation import recommendation_for, risk_level

TIER1_FIELDS = [
    "sleep_duration_minutes",
    "sleep_efficiency",
    "resting_heart_rate",
    "mean_heart_rate",
    "step_count",
    "activity_minutes",
    "age",
    "sex",
]

TIER2_FIELDS = TIER1_FIELDS + [
    "urge_to_move_legs",
    "worse_at_rest",
    "relieved_by_movement",
    "worse_in_evening_or_night",
    "sleep_disturbance_score",
    "symptom_frequency",
    "symptom_severity",
]


def _sigmoid(value: float) -> float:
    return 1.0 / (1.0 + exp(-value))


def _sex_value(sex: str | None) -> float:
    if sex is None:
        return 0.0
    normalized = sex.strip().lower()
    if normalized in {"male", "m", "man", "男", "1"}:
        return 0.08
    if normalized in {"female", "f", "woman", "女", "0"}:
        return -0.02
    return 0.0


def _fallback_score(features: dict[str, Any], tier: str) -> tuple[float, dict[str, Any]]:
    sleep_duration = features.get("sleep_duration_minutes") or 420
    sleep_efficiency = features.get("sleep_efficiency") or 85
    resting_hr = features.get("resting_heart_rate") or 62
    mean_hr = features.get("mean_heart_rate") or resting_hr
    steps = features.get("step_count") or 6500
    activity = features.get("activity_minutes") or 30
    age = features.get("age") or 45
    missing_count = sum(1 for missing in (features.get("missing_mask_json") or {}).values() if missing)

    z = -1.25
    z += max(0, 420 - sleep_duration) / 180 * 0.42
    z += max(0, 85 - sleep_efficiency) / 20 * 0.38
    z += max(0, resting_hr - 70) / 25 * 0.22
    z += max(0, mean_hr - 78) / 30 * 0.16
    z += max(0, 5000 - steps) / 5000 * 0.18
    z += max(0, 20 - activity) / 30 * 0.16
    z += max(0, age - 45) / 30 * 0.18
    z += _sex_value(features.get("sex"))
    z += min(missing_count, 5) * 0.04

    questionnaire_signal = 0.0
    if tier == "tier2":
        questionnaire_signal = (
            ((features.get("urge_to_move_legs") or 0) / 4) * 0.44
            + ((features.get("worse_at_rest") or 0) / 4) * 0.34
            + ((features.get("relieved_by_movement") or 0) / 4) * 0.26
            + ((features.get("worse_in_evening_or_night") or 0) / 4) * 0.34
            + ((features.get("sleep_disturbance_score") or 0) / 10) * 0.22
            + ((features.get("symptom_frequency") or 0) / 7) * 0.20
            + ((features.get("symptom_severity") or 0) / 10) * 0.26
        )
        z += questionnaire_signal

    score = round(min(max(_sigmoid(z), 0.0), 1.0), 4)
    explanation = {
        "mode": "deterministic_fallback",
        "signals": {
            "short_or_fragmented_sleep": sleep_duration < 390 or sleep_efficiency < 80,
            "elevated_heart_rate": resting_hr > 70 or mean_hr > 78,
            "low_activity": steps < 5000 or activity < 20,
            "questionnaire_signal": round(questionnaire_signal, 4),
            "missing_fields": missing_count,
        },
    }
    return score, explanation


def _artifact_predict(model: Any, features: dict[str, Any], tier: str) -> tuple[float, dict[str, Any]]:
    if isinstance(model, object) and model.__class__.__name__ == "RLSExperimentModelAdapter":
        score = model.predict_proba(features)
        meta = getattr(model, "meta", None) or {}
        return score, {
            "mode": "rls_experiments_xgb_tabm_adapter",
            "scenario": meta.get("scenario"),
            "resolution": meta.get("resolution"),
            "train_prevalence": meta.get("train_prevalence"),
            "prevalence_adjusted": getattr(model, "apply_prevalence_adjustment", None),
            "population_prevalence": getattr(model, "population_prevalence", None),
            "feature_projection": "mvp_schema_to_rls_experiment_features_v1",
        }
    ordered = TIER2_FIELDS if tier == "tier2" else TIER1_FIELDS
    vector = [[features.get(field) for field in ordered]]
    if hasattr(model, "predict_proba"):
        score = float(model.predict_proba(vector)[0][1])
    elif hasattr(model, "predict"):
        score = float(model.predict(vector)[0])
    else:
        raise TypeError("Loaded model must expose predict_proba or predict.")
    return round(min(max(score, 0.0), 1.0), 4), {"mode": "artifact", "feature_order": ordered}


def predict_tier1(payload: Tier1FeatureInput) -> PredictionResponse:
    return _predict(payload.model_dump(), "tier1")


def predict_tier2(payload: Tier2FeatureInput) -> PredictionResponse:
    return _predict(payload.model_dump(), "tier2")


def _predict(features: dict[str, Any], tier: str) -> PredictionResponse:
    model = model_registry.load(tier)
    using_fallback = model is None
    if using_fallback:
        score, explanation = _fallback_score(features, tier)
    else:
        try:
            score, explanation = _artifact_predict(model, features, tier)
        except ModelAdapterUnavailable as exc:
            using_fallback = True
            score, explanation = _fallback_score(features, tier)
            explanation["fallback_reason"] = str(exc)

    level = risk_level(score)
    explanation["schema"] = "rls-screening-feature-schema-v1"
    explanation["tier"] = tier
    explanation["source_note"] = "Real XGBoost/TabM adapter is available when model files and optional model dependencies are installed."
    return PredictionResponse(
        risk_score=score,
        risk_level=level,
        model_version=model_registry.version(tier, using_fallback, model),
        explanation_json=explanation,
        recommendation_text=recommendation_for(level),
    )
