# HealthKit Collaborator Brief

## Goal

Implement real Apple HealthKit / Apple Health data sync for the Flutter mobile scaffold while keeping the backend and prediction logic unchanged.

## Current State

The backend wearable ingestion API is ready:

```text
POST /wearable/upload
GET /wearable/daily-features
```

The mobile app currently uses `MockHealthDataService` in:

```text
apps/mobile/lib/main.dart
```

Please add a real iOS implementation behind the same `HealthDataService` interface.

## Required Scope

- Request Apple HealthKit permissions for:
  - sleep analysis
  - heart rate
  - resting heart rate
  - step count
  - activity or exercise minutes if safely available
- Read recent Apple Health data from the device.
- Normalize records into the backend wearable event format.
- Upload normalized events to `POST /wearable/upload`.
- Keep `MockHealthDataService` working for local development.
- Document required iOS entitlements, `Info.plist` strings, permission prompts, and real-device testing requirements.

## Out Of Scope

- Do not change prediction/model logic.
- Do not remove mock data sync.
- Do not build Android Health Connect in this task.
- Do not add clinical diagnosis claims.

## Backend Event Format

```json
{
  "events": [
    {
      "source": "apple_healthkit",
      "data_type": "sleep",
      "start_time": "2026-07-02T00:00:00Z",
      "end_time": "2026-07-02T07:00:00Z",
      "value_json": {
        "duration_minutes": 410,
        "sleep_efficiency": 82
      }
    },
    {
      "source": "apple_healthkit",
      "data_type": "heart_rate",
      "start_time": "2026-07-02T06:00:00Z",
      "end_time": "2026-07-02T06:10:00Z",
      "value_json": {
        "bpm": 74,
        "resting_bpm": 66
      }
    },
    {
      "source": "apple_healthkit",
      "data_type": "steps",
      "start_time": "2026-07-02T08:00:00Z",
      "end_time": "2026-07-02T20:00:00Z",
      "value_json": {
        "count": 6200
      }
    },
    {
      "source": "apple_healthkit",
      "data_type": "activity",
      "start_time": "2026-07-02T18:00:00Z",
      "end_time": "2026-07-02T18:26:00Z",
      "value_json": {
        "duration_minutes": 26
      }
    }
  ]
}
```

## Relevant Files

- `apps/mobile/lib/main.dart`
- `services/api/app/api/routes_wearable.py`
- `services/api/app/schemas/wearable.py`
- `services/api/app/services/feature_engineering.py`
- `docs/API_SCHEMA.md`
- `docs/DATA_DICTIONARY.md`

## Suggested GitHub Issue Title

```text
Implement Apple HealthKit adapter for Flutter mobile HealthDataService
```

## Suggested Handoff Summary

```text
The backend already accepts normalized wearable events and converts them into daily features for model input. Please implement Apple HealthKit data reads in the Flutter mobile app behind HealthDataService, then upload normalized events to POST /wearable/upload. Keep mock sync available for local development.
```
