# API Schema

Base URL: `http://localhost:8000`

- `GET /health`: backend health check.
- `POST /auth/register`: creates user, profile, and MVP consent record.
- `POST /auth/login`: returns bearer token.
- `GET /users/me`: returns current user and profile.
- `POST /wearable/upload`: uploads mock or normalized wearable events.
- `GET /wearable/daily-features`: returns aggregated daily features.
- `POST /questionnaire/submit`: stores Tier 2 questionnaire responses.
- `GET /questionnaire/history`: returns questionnaire history.
- `POST /predict/tier1`: wearable-only prediction.
- `POST /predict/tier2`: wearable plus questionnaire prediction.
- `GET /predictions/history`: returns prediction history.
- `GET /reports/latest`: returns latest prediction, daily features, and questionnaire.

Tier 1 request:

```json
{
  "sleep_duration_minutes": 405,
  "sleep_efficiency": 80,
  "resting_heart_rate": 69,
  "mean_heart_rate": 78,
  "step_count": 5200,
  "activity_minutes": 26,
  "age": 51,
  "sex": "female",
  "height": 165,
  "weight": 62,
  "min_heart_rate": 58,
  "max_heart_rate": 104,
  "missing_mask_json": {}
}
```

Prediction response:

```json
{
  "risk_score": 0.42,
  "risk_level": "moderate",
  "model_version": "tier1-fallback-2026-07-01",
  "explanation_json": {},
  "recommendation_text": "Non-diagnostic guidance text",
  "disclaimer_text": "This is a non-diagnostic screening risk estimate..."
}
```
