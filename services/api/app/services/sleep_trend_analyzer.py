from __future__ import annotations

from datetime import datetime
from statistics import pstdev

from app.db.models import DailyFeature
from app.schemas.agent import SleepTrendSummary


def analyze_sleep_trends(features: list[DailyFeature]) -> SleepTrendSummary:
    ordered = sorted(features, key=lambda item: item.date, reverse=True)[:14]
    latest = ordered[0] if ordered else None
    recent = ordered[:7]
    previous = ordered[7:14]

    avg_sleep_7d = _avg([item.sleep_duration_minutes for item in recent])
    avg_sleep_prev_7d = _avg([item.sleep_duration_minutes for item in previous])
    avg_eff_7d = _avg([item.sleep_efficiency for item in recent])
    bedtime_variability = _time_variability([item.bed_time for item in recent])
    wake_time_variability = _time_variability([item.wake_time for item in recent])
    awakenings_recent = _avg([item.night_awakenings for item in recent])
    awakenings_previous = _avg([item.night_awakenings for item in previous])
    rls_nights = sum(1 for item in recent if (item.rls_symptom_score or 0) >= 1)
    osa_warning = any(_has_osa_signal(item) for item in recent)

    sleep_change = None
    if avg_sleep_7d is not None and avg_sleep_prev_7d is not None:
        sleep_change = round(avg_sleep_7d - avg_sleep_prev_7d, 2)

    awakenings_change = None
    if awakenings_recent is not None and awakenings_previous is not None:
        awakenings_change = round(awakenings_recent - awakenings_previous, 2)

    short_sleep = avg_sleep_7d is not None and avg_sleep_7d < 420
    irregular_schedule = (
        (bedtime_variability is not None and bedtime_variability >= 60)
        or (wake_time_variability is not None and wake_time_variability >= 60)
    )
    possible_rls = rls_nights >= 3

    risk_flags: list[str] = []
    if short_sleep:
        risk_flags.append("short_sleep")
    if irregular_schedule:
        risk_flags.append("irregular_schedule")
    if possible_rls:
        risk_flags.append("possible_rls_pattern")
    if osa_warning:
        risk_flags.append("possible_osa_warning")

    return SleepTrendSummary(
        avg_sleep_7d=avg_sleep_7d,
        avg_sleep_prev_7d=avg_sleep_prev_7d,
        sleep_duration_change=sleep_change,
        avg_sleep_efficiency_7d=avg_eff_7d,
        bedtime_variability_minutes=bedtime_variability,
        wake_time_variability_minutes=wake_time_variability,
        night_awakenings_change=awakenings_change,
        rls_symptom_nights=rls_nights,
        short_sleep_flag=short_sleep,
        irregular_schedule_flag=irregular_schedule,
        possible_rls_pattern_flag=possible_rls,
        possible_osa_warning_flag=osa_warning,
        latest_sleep_duration_minutes=latest.sleep_duration_minutes if latest else None,
        latest_sleep_efficiency=latest.sleep_efficiency if latest else None,
        latest_resting_heart_rate=latest.resting_heart_rate if latest else None,
        latest_mean_heart_rate=latest.mean_heart_rate if latest else None,
        latest_step_count=latest.step_count if latest else None,
        latest_activity_minutes=latest.activity_minutes if latest else None,
        risk_flags=risk_flags,
    )


def _avg(values: list[float | int | None]) -> float | None:
    valid = [float(value) for value in values if value is not None]
    if not valid:
        return None
    return round(sum(valid) / len(valid), 2)


def _time_variability(values: list[str | None]) -> float | None:
    minutes = [_clock_to_minutes(value) for value in values if value]
    if len(minutes) < 2:
        return None
    return round(pstdev(minutes), 2)


def _clock_to_minutes(value: str) -> int:
    parsed = datetime.strptime(value, "%H:%M")
    return parsed.hour * 60 + parsed.minute


def _has_osa_signal(item: DailyFeature) -> bool:
    note = (item.notes or "").lower()
    return (
        (item.daytime_sleepiness_score or 0) >= 7
        or "snore" in note
        or "打鼾" in note
        or "apnea" in note
        or "呼吸暂停" in note
        or "憋醒" in note
    )
