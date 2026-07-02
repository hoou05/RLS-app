# RLS Screening App MVP

Runnable monorepo scaffold for a Restless Legs Syndrome screening workflow. The app produces non-diagnostic risk estimates from wearable-style data and questionnaire responses.

This is an MVP scaffold, not a clinical product. It is meant to prove that the backend, database, model adapter/fallback, web dashboard, and mobile health-data interface can work together.

## What Is Included

- `services/api`: FastAPI backend, SQLModel schema, auth, wearable upload, questionnaire, prediction, reports, and tests.
- `apps/web`: Vite React dashboard for registration/login, mock wearable sync, questionnaire/prediction flow, histories, model info, and a polished green RLS-themed UI.
- `apps/mobile`: Flutter scaffold with login, consent, health permission, dashboard, questionnaire, result, history, mocked health-data sync, and a HealthKit/Health Connect interface boundary.
- `packages/shared_schema`: JSON schema for stable MVP feature payloads.
- `services/api/model_artifacts`: small exported XGBoost/TabM artifact folders from the RLS experiments plus adapter documentation.
- `docker-compose.yml`: PostgreSQL, API, and web services.

## Architecture

```text
Web dashboard / Flutter scaffold
        |
        | register/login, wearable upload, questionnaire, prediction
        v
FastAPI service
        |
        | SQLModel ORM
        v
SQLite locally / PostgreSQL in Docker
        |
        | daily feature aggregation
        v
Model registry
        |
        | real XGBoost/TabM adapter if optional deps are installed
        | deterministic fallback otherwise
        v
Prediction + latest report APIs
```

## Local Setup

Backend:

```bash
cd services/api
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Backend docs:

- API docs: `http://localhost:8000/docs`
- Health check: `http://localhost:8000/health`

Web:

```bash
cd apps/web
npm install
npm run dev
```

Web URL:

```text
http://localhost:5173
```

Mobile scaffold:

```bash
cd apps/mobile
flutter pub get
flutter run
```

Docker:

```bash
docker compose up --build
```

## Recommended MVP Test Flow

1. Start FastAPI on `http://localhost:8000`.
2. Start the web app on `http://localhost:5173`.
3. Register a demo user.
4. Click `Sync mock health data`.
5. Click `Submit questionnaire + predict`.
6. Check the dashboard risk score.
7. Open `Prediction history`, `Questionnaire history`, and `Upload/debug` to verify that data was saved.
8. Open `http://localhost:8000/docs` for raw API testing.

## Current Data Sources

Current wearable and questionnaire values are test data:

- Web `Sync mock health data` posts mocked sleep, heart rate, step, and activity events.
- Web `Submit questionnaire + predict` posts a fixed MVP questionnaire payload.
- Flutter currently uses `MockHealthDataService`.

The backend ingestion path is real and ready:

- `POST /wearable/upload`
- `GET /wearable/daily-features`
- `POST /questionnaire/submit`
- `POST /predict/tier1`
- `POST /predict/tier2`
- `GET /reports/latest`

Real Apple HealthKit / Apple Health and Android Health Connect integration should be added behind the mobile `HealthDataService` interface without changing backend model logic.

## Model Behavior

The backend exposes a unified inference path:

```text
predict_proba(feature_dict) -> float
```

It attempts to use the real XGBoost/TabM artifacts when optional model dependencies and artifact files are available. If they are not available, it uses deterministic fallback inference so local development does not break.

Install optional model dependencies:

```bash
cd services/api
source .venv/bin/activate
pip install -r requirements-model.txt
```

Fallback mode is expected during ordinary MVP debugging. The report explanation includes `mode: deterministic_fallback` when fallback is active.

## Validation

Backend:

```bash
cd services/api
source .venv/bin/activate
pytest
```

Web:

```bash
cd apps/web
npm run build
```

Mobile:

```bash
cd apps/mobile
flutter analyze
```

## Known Issues And MVP Boundaries

- This app is non-diagnostic and should not be used as a clinical diagnosis.
- Real HealthKit / Apple Health and Android Health Connect sync is not implemented yet.
- The web and mobile apps still use mock health data.
- Production-grade auth, consent versioning, audit logs, migrations, and regulatory controls are out of scope.
- The real model adapter maps MVP fields into exported experiment artifacts; missing feature parity is expected until the production feature contract is finalized.
- Flutter SDK is required to run the mobile app; the backend and web can be tested without Flutter.

## More Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [API Schema](docs/API_SCHEMA.md)
- [Data Dictionary](docs/DATA_DICTIONARY.md)
- [Model Card](docs/MODEL_CARD.md)
- [Privacy And Security](docs/PRIVACY_AND_SECURITY.md)
- [Debugging Guide](docs/DEBUGGING.md)
- [Virtual Debug Environment](docs/VIRTUAL_DEBUG_ENVIRONMENT.md)
- [HealthKit Collaborator Brief](docs/HEALTHKIT_COLLABORATOR_BRIEF.md)

This app is for screening risk estimates only. It does not diagnose RLS or determine whether a user has RLS.
