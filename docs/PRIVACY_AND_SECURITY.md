# Privacy And Security

## Current MVP

- Registration stores email, hashed password, profile fields, and consent version.
- Wearable data is normalized before feature aggregation.
- Audit logs record key actions.
- The app states that outputs are screening risk estimates, not diagnoses.

## Data Minimization

The MVP daily feature table stores aggregated features needed for screening. Raw wearable events are retained only to support debugging and future feature engineering.

## Consent

The registration flow creates an MVP consent record. A production app should use a fuller ResearchKit-style consent flow with versioned consent documents and withdrawal handling.

## Future Controls

- Add database migrations and retention policies.
- Add encryption at rest and in transit.
- Add role-based access control.
- Add HIPAA/GDPR-style data rights workflows where applicable.
- Add clinical validation, safety review, monitoring, and incident response before any real deployment.
