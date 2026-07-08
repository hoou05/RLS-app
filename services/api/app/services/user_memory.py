from __future__ import annotations

from collections import Counter

from sqlmodel import Session, select

from app.db.models import AgentFeedback, DailyFeature, UserMemory, utcnow
from app.schemas.agent import AgentFeedbackRequest, PersonalBaseline, UserMemoryRead


def get_or_create_memory(session: Session, user_id: int) -> UserMemory:
    memory = session.exec(select(UserMemory).where(UserMemory.user_id == user_id)).first()
    if memory:
        return memory
    memory = UserMemory(user_id=user_id)
    session.add(memory)
    session.commit()
    session.refresh(memory)
    return memory


def build_personal_baseline(features: list[DailyFeature]) -> PersonalBaseline:
    valid_sleep = [item.sleep_duration_minutes for item in features if item.sleep_duration_minutes is not None]
    valid_efficiency = [item.sleep_efficiency for item in features if item.sleep_efficiency is not None]
    bed_times = [item.bed_time for item in features if item.bed_time]
    wake_times = [item.wake_time for item in features if item.wake_time]
    days = len({item.date for item in features})
    rls_nights = sum(1 for item in features if (item.rls_symptom_score or 0) >= 1)
    confidence = "high" if days >= 21 else "medium" if days >= 7 else "low"
    return PersonalBaseline(
        usual_sleep_minutes=_avg(valid_sleep),
        usual_sleep_efficiency=_avg(valid_efficiency),
        usual_bed_time=_mode(bed_times),
        usual_wake_time=_mode(wake_times),
        rls_symptom_rate=round(rls_nights / days, 2) if days else None,
        data_days=days,
        confidence=confidence,
    )


def refresh_memory_baseline(session: Session, user_id: int, features: list[DailyFeature]) -> UserMemory:
    memory = get_or_create_memory(session, user_id)
    baseline = build_personal_baseline(features)
    memory.baseline_json = baseline.model_dump()
    memory.updated_at = utcnow()
    session.add(memory)
    session.commit()
    session.refresh(memory)
    return memory


def record_feedback(session: Session, user_id: int, payload: AgentFeedbackRequest) -> UserMemory:
    feedback = AgentFeedback(
        user_id=user_id,
        rating=payload.rating,
        reason=payload.reason,
        question=payload.question,
        answer_excerpt=payload.answer_excerpt,
        metadata_json=payload.metadata,
    )
    session.add(feedback)
    memory = get_or_create_memory(session, user_id)
    summary = dict(memory.feedback_summary_json or {})
    summary[payload.rating] = int(summary.get(payload.rating, 0)) + 1
    if payload.rating in {"too_generic", "already_tried"} and payload.reason:
        avoid = list(memory.avoid_repeating_json or [])
        if payload.reason not in avoid:
            avoid.append(payload.reason)
        memory.avoid_repeating_json = avoid[-12:]
    if payload.rating == "too_complex":
        memory.preferred_answer_style = "simple"
    memory.feedback_summary_json = summary
    memory.updated_at = utcnow()
    session.add(memory)
    session.commit()
    session.refresh(memory)
    return memory


def memory_to_read(memory: UserMemory | None) -> UserMemoryRead:
    if not memory:
        return UserMemoryRead()
    return UserMemoryRead(
        preferred_language=memory.preferred_language,
        preferred_answer_style=memory.preferred_answer_style,
        avoid_repeating=list(memory.avoid_repeating_json or []),
        learned_facts=dict(memory.learned_facts_json or {}),
        feedback_summary=dict(memory.feedback_summary_json or {}),
    )


def _avg(values: list[float | int]) -> float | None:
    if not values:
        return None
    return round(sum(float(value) for value in values) / len(values), 2)


def _mode(values: list[str]) -> str | None:
    if not values:
        return None
    return Counter(values).most_common(1)[0][0]
