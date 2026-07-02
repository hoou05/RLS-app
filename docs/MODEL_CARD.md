# Model Card

## Intended Use

This MVP estimates screening risk patterns for Restless Legs Syndrome workflows. It is not a diagnosis system and should not be used to determine whether a person has RLS.

## Model Tiers

- Tier 1: wearable-only features, including sleep, heart rate, steps, activity, age, and sex.
- Tier 2: Tier 1 features plus questionnaire responses.

## Current MVP Behavior

The API tries to load:

- `services/api/model_artifacts/tier1_model.pkl`
- `services/api/model_artifacts/tier2_model.pkl`

If those artifacts are absent, it uses a deterministic fallback scorer. The fallback is for product and API development only.

The MVP also supports the supplied XGBoost + TabM experiment directories:

- `services/api/model_artifacts/rls_experiments/sleep_heart_basic__apple`
- `services/api/model_artifacts/rls_experiments/sleep_heart_basic_q__apple`

Install optional model dependencies before using those artifacts:

```bash
cd services/api
pip install -r requirements-model.txt
```

The adapter lives in `app/services/rls_experiments_adapter.py` and exposes `predict_proba(feature_dict) -> float`. It maps the simplified MVP schema into the Chinese feature names used by the experiment repository. Features that the MVP does not collect yet, such as sleep stages, SpO2, exact min/max heart-rate deltas, and legacy clinical questionnaire fields, remain missing and are handled by the model's original missing-data pathway.

## Existing Experiment Repository

The supplied `rls-prediction-experiments` archive contains XGBoost `.ubj`, TabM `.pt`, preprocessing artifacts, and scenario metadata. The strongest scenario described in the archive is sleep + heart + basic + questionnaire. The MVP uses Apple-resolution `sleep_heart_basic` for Tier 1 and Apple-resolution `sleep_heart_basic_q` for Tier 2.

## Versioning Plan

Every prediction includes `model_version`. Fallback versions use `tier1-fallback-2026-07-01` or `tier2-fallback-2026-07-01`. Real model versions should include training data version, feature schema version, calibration version, and artifact hash.
