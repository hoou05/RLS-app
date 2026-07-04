from collections.abc import Generator

from sqlalchemy import inspect, text
from sqlmodel import Session, SQLModel, create_engine

from app.core.config import get_settings
from app.db.models import DailyFeature

settings = get_settings()
connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, echo=False, connect_args=connect_args)


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _migrate_sqlite_daily_features()


def _migrate_sqlite_daily_features() -> None:
    if not settings.database_url.startswith("sqlite"):
        return

    inspector = inspect(engine)
    if "dailyfeature" not in inspector.get_table_names():
        return

    existing_columns = {column["name"] for column in inspector.get_columns("dailyfeature")}
    dialect = engine.dialect
    with engine.begin() as connection:
        for column in DailyFeature.__table__.columns:
            if column.name in existing_columns:
                continue
            column_type = column.type.compile(dialect=dialect)
            default = " DEFAULT '{}'" if column.name == "missing_mask_json" else ""
            connection.execute(text(f'ALTER TABLE dailyfeature ADD COLUMN "{column.name}" {column_type}{default}'))


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
