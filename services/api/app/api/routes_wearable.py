from fastapi import APIRouter
from sqlmodel import select

from app.api.deps import CurrentUser, SessionDep
from app.db.models import AuditLog, DailyFeature, WearableRawData, utcnow
from app.schemas.wearable import DailyFeatureRead, WearableUploadRequest, WearableUploadResponse
from app.services.feature_engineering import aggregate_daily_features

router = APIRouter(prefix="/wearable", tags=["wearable"])


@router.post("/upload", response_model=WearableUploadResponse)
def upload(payload: WearableUploadRequest, current_user: CurrentUser, session: SessionDep) -> WearableUploadResponse:
    raw_events = [
        WearableRawData(
            user_id=current_user.id,
            source=event.source,
            data_type=event.data_type,
            start_time=event.start_time,
            end_time=event.end_time,
            value_json=event.value_json,
        )
        for event in payload.events
    ]
    for event in raw_events:
        session.add(event)
    session.commit()

    daily_features = aggregate_daily_features(current_user.id, raw_events)
    for feature in daily_features:
        existing = session.exec(
            select(DailyFeature).where(
                DailyFeature.user_id == current_user.id,
                DailyFeature.date == feature.date,
            )
        ).first()
        if existing:
            existing.bed_time = feature.bed_time
            existing.wake_time = feature.wake_time
            existing.sleep_duration_minutes = feature.sleep_duration_minutes
            existing.time_in_bed_minutes = feature.time_in_bed_minutes
            existing.sleep_efficiency = feature.sleep_efficiency
            existing.sleep_latency_minutes = feature.sleep_latency_minutes
            existing.night_awakenings = feature.night_awakenings
            existing.resting_heart_rate = feature.resting_heart_rate
            existing.mean_heart_rate = feature.mean_heart_rate
            existing.hrv = feature.hrv
            existing.step_count = feature.step_count
            existing.activity_minutes = feature.activity_minutes
            existing.daytime_sleepiness_score = feature.daytime_sleepiness_score
            existing.rls_symptom_score = feature.rls_symptom_score
            existing.caffeine_evening = feature.caffeine_evening
            existing.alcohol_evening = feature.alcohol_evening
            existing.exercise = feature.exercise
            existing.notes = feature.notes
            existing.missing_mask_json = feature.missing_mask_json
            existing.created_at = utcnow()
            session.add(existing)
        else:
            session.add(feature)
    session.add(AuditLog(user_id=current_user.id, action="wearable.upload", metadata_json={"events": len(raw_events)}))
    session.commit()
    return WearableUploadResponse(imported_events=len(raw_events), generated_daily_features=len(daily_features))


@router.get("/daily-features", response_model=list[DailyFeatureRead])
def daily_features(current_user: CurrentUser, session: SessionDep) -> list[DailyFeature]:
    statement = (
        select(DailyFeature)
        .where(DailyFeature.user_id == current_user.id)
        .order_by(DailyFeature.date.desc(), DailyFeature.created_at.desc(), DailyFeature.id.desc())
    )
    return list(session.exec(statement).all())
