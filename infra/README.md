# Infrastructure Notes

Docker compose is the MVP local environment:

- `postgres`: PostgreSQL 16
- `api`: FastAPI + SQLModel
- `web`: Vite React dashboard

Future production work should add migrations, secret management, HTTPS, managed database backups, audit-log retention, and deployment-specific observability.
