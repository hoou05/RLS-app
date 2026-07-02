# Architecture

The MVP keeps model inference inside the FastAPI service while preserving a service boundary so it can move out later.

```mermaid
flowchart LR
  Mobile["Flutter mobile scaffold"] --> API["FastAPI backend"]
  Web["Vite React dashboard"] --> API
  API --> DB[("PostgreSQL or local SQLite")]
  API --> ML["Inference module"]
  ML --> Artifacts["tier1_model.pkl / tier2_model.pkl"]
  ML --> Fallback["Deterministic fallback scorer"]
  Mobile --> Health["HealthDataService interface"]
  Health --> Mock["Mock data now"]
  Health -. TODO .-> HealthKit["Apple HealthKit"]
  Health -. TODO .-> HealthConnect["Android Health Connect"]
```

The structure follows the FastAPI full-stack template pattern at a smaller scale: backend service, React web app, database, Docker compose, and documentation. Health integrations follow a modular interface inspired by Health Connect, Flutter `health`, Open Wearables, ResearchKit, and CareKit, but the MVP does not depend on native health APIs.
