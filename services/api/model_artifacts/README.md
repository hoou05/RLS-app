# Model Artifacts

Place deployable MVP artifacts here:

- `tier1_model.pkl`
- `tier2_model.pkl`

The API currently tries these files first. If they are absent, it uses the deterministic fallback scoring function in `app/services/inference.py`.

The exported `rls-prediction-experiments` XGBoost + TabM artifacts are stored under:

- `rls_experiments/sleep_heart_basic__apple`
- `rls_experiments/sleep_heart_basic_q__apple`

The adapter is `app/services/rls_experiments_adapter.py` and exposes `predict_proba(feature_dict) -> float`.

Install optional model dependencies before using those artifacts:

```bash
pip install -r requirements-model.txt
```

If optional dependencies are missing, the API falls back to deterministic MVP scoring instead of breaking local development.
