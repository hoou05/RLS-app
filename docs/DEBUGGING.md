# Debugging Guide

This guide explains how to run and debug the RLS screening MVP locally.

## Services

Backend:

```bash
cd services/api
source .venv/bin/activate
uvicorn app.main:app --reload
```

Web:

```bash
cd apps/web
npm run dev
```

Open:

- Web app: `http://localhost:5173`
- Swagger API docs: `http://localhost:8000/docs`

## Expected Happy Path

1. Register a demo user in the web app.
2. Confirm backend logs show `POST /auth/register 200 OK`.
3. Click `Sync mock health data`.
4. Confirm backend logs show `POST /wearable/upload 200 OK`.
5. Click `Submit questionnaire + predict`.
6. Confirm backend logs show:
   - `POST /questionnaire/submit 200 OK`
   - `POST /predict/tier2 200 OK`
   - `GET /reports/latest 200 OK`
7. Confirm the dashboard risk score updates.

## What The Debug Tabs Mean

`Prediction history` is a developer/debug view. It confirms that predictions are saved with risk score, tier, model version, explanation, and timestamp.

`Questionnaire history` is a developer/debug view. It confirms that questionnaire payloads are saved and can be used for Tier 2 prediction.

`Upload/debug` shows aggregated daily features from uploaded wearable events.

These views are intentionally raw. A patient-facing product should replace them with trends, summaries, and clinician-facing reports.

## Common Issues

### Web Shows "Cannot reach the backend"

FastAPI is not running or the web app is pointing to the wrong API URL.

Check:

```bash
curl http://localhost:8000/health
```

If this fails, restart the backend.

### Register Or Login Returns 401

The token is missing, expired, or the email/password is wrong.

Use Swagger docs:

1. Open `http://localhost:8000/docs`.
2. Register or login.
3. Authorize with the bearer token.
4. Try `GET /users/me`.

### 422 Validation Error

The request body does not match the Pydantic schema. Swagger shows which field failed.

Common examples:

- Password too short.
- Missing `consent_version`.
- Wrong numeric type for age, height, or weight.

### Risk Score Stays Empty

Run the full sequence:

1. Sync mock health data.
2. Submit questionnaire + predict.
3. Refresh dashboard.

The dashboard cannot show a prediction until `POST /predict/tier2` has successfully created one.

### Fallback Model Is Used

This is expected unless optional model dependencies are installed.

Install optional dependencies:

```bash
cd services/api
source .venv/bin/activate
pip install -r requirements-model.txt
```

The latest report explains model mode under `latest_prediction.explanation_json.mode`.

### Mobile App Does Not Run

The mobile scaffold requires Flutter SDK.

Check:

```bash
flutter --version
```

If Flutter is not installed, you can still test the backend and web app.

## Validation Commands

Backend tests:

```bash
cd services/api
source .venv/bin/activate
pytest
```

Web build:

```bash
cd apps/web
npm run build
```

Flutter analyze:

```bash
cd apps/mobile
flutter analyze
```

## Reading Backend Logs

Healthy local interaction usually looks like:

```text
POST /auth/register 200 OK
GET /reports/latest 200 OK
POST /wearable/upload 200 OK
GET /wearable/daily-features 200 OK
POST /questionnaire/submit 200 OK
POST /predict/tier2 200 OK
GET /reports/latest 200 OK
```

`OPTIONS` requests are normal browser CORS preflight requests.
