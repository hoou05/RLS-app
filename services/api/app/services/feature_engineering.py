from collections import defaultdict
from datetime import date

from app.db.models import DailyFeature, WearableRawData


def aggregate_daily_features(user_id: int, events: list[WearableRawData]) -> list[DailyFeature]:
    grouped: dict[date, list[WearableRawData]] = defaultdict(list)
    for event in events:
        grouped[event.start_time.date()].append(event)

    features: list[DailyFeature] = []
    for day, day_events in grouped.items():
        sleep_minutes: list[float] = []
        time_in_bed_minutes: list[float] = []
        sleep_efficiencies: list[float] = []
        sleep_latency_minutes: list[float] = []
        night_awakenings: list[int] = []
        heart_rates: list[float] = []
        resting_rates: list[float] = []
        hrv_values: list[float] = []
        steps = 0
        activity_minutes = 0.0
        bedtime: str | None = None
        wake_time: str | None = None
        daytime_sleepiness_score: int | None = None
        rls_symptom_score: int | None = None
        caffeine_evening: bool | None = None
        alcohol_evening: bool | None = None
        exercise: bool | None = None
        notes: str | None = None

        for event in day_events:
            value = event.value_json
            if event.data_type == "sleep":
                if value.get("bed_time") is not None:
                    bedtime = str(value["bed_time"])
                if value.get("wake_time") is not None:
                    wake_time = str(value["wake_time"])
                if value.get("duration_minutes") is not None:
                    sleep_minutes.append(float(value["duration_minutes"]))
                if value.get("time_in_bed_minutes") is not None:
                    time_in_bed_minutes.append(float(value["time_in_bed_minutes"]))
                if value.get("sleep_efficiency") is not None:
                    sleep_efficiencies.append(float(value["sleep_efficiency"]))
                if value.get("sleep_latency_minutes") is not None:
                    sleep_latency_minutes.append(float(value["sleep_latency_minutes"]))
                if value.get("night_awakenings") is not None:
                    night_awakenings.append(int(value["night_awakenings"]))
                if value.get("daytime_sleepiness_score") is not None:
                    daytime_sleepiness_score = int(value["daytime_sleepiness_score"])
                if value.get("rls_symptom_score") is not None:
                    rls_symptom_score = int(value["rls_symptom_score"])
                if value.get("caffeine_evening") is not None:
                    caffeine_evening = bool(value["caffeine_evening"])
                if value.get("alcohol_evening") is not None:
                    alcohol_evening = bool(value["alcohol_evening"])
                if value.get("exercise") is not None:
                    exercise = bool(value["exercise"])
                if value.get("notes") is not None:
                    notes = str(value["notes"])
            elif event.data_type == "heart_rate":
                if value.get("bpm") is not None:
                    heart_rates.append(float(value["bpm"]))
                if value.get("resting_bpm") is not None:
                    resting_rates.append(float(value["resting_bpm"]))
                if value.get("hrv") is not None:
                    hrv_values.append(float(value["hrv"]))
            elif event.data_type == "steps":
                steps += int(value.get("count") or 0)
            elif event.data_type == "activity":
                activity_minutes += float(value.get("duration_minutes") or 0)
                if value.get("exercise") is not None:
                    exercise = bool(value["exercise"])

        record = DailyFeature(
            user_id=user_id,
            date=day,
            bed_time=bedtime,
            wake_time=wake_time,
            sleep_duration_minutes=sum(sleep_minutes) if sleep_minutes else None,
            time_in_bed_minutes=sum(time_in_bed_minutes) if time_in_bed_minutes else None,
            sleep_efficiency=(sum(sleep_efficiencies) / len(sleep_efficiencies)) if sleep_efficiencies else None,
            sleep_latency_minutes=(sum(sleep_latency_minutes) / len(sleep_latency_minutes)) if sleep_latency_minutes else None,
            night_awakenings=(sum(night_awakenings) // len(night_awakenings)) if night_awakenings else None,
            resting_heart_rate=(sum(resting_rates) / len(resting_rates)) if resting_rates else None,
            mean_heart_rate=(sum(heart_rates) / len(heart_rates)) if heart_rates else None,
            hrv=(sum(hrv_values) / len(hrv_values)) if hrv_values else None,
            step_count=steps if steps else None,
            activity_minutes=activity_minutes if activity_minutes else None,
            daytime_sleepiness_score=daytime_sleepiness_score,
            rls_symptom_score=rls_symptom_score,
            caffeine_evening=caffeine_evening,
            alcohol_evening=alcohol_evening,
            exercise=exercise,
            notes=notes,
        )
        record.missing_mask_json = {
            "bed_time": record.bed_time is None,
            "wake_time": record.wake_time is None,
            "sleep_duration_minutes": record.sleep_duration_minutes is None,
            "time_in_bed_minutes": record.time_in_bed_minutes is None,
            "sleep_efficiency": record.sleep_efficiency is None,
            "sleep_latency_minutes": record.sleep_latency_minutes is None,
            "night_awakenings": record.night_awakenings is None,
            "resting_heart_rate": record.resting_heart_rate is None,
            "mean_heart_rate": record.mean_heart_rate is None,
            "hrv": record.hrv is None,
            "step_count": record.step_count is None,
            "activity_minutes": record.activity_minutes is None,
            "daytime_sleepiness_score": record.daytime_sleepiness_score is None,
            "rls_symptom_score": record.rls_symptom_score is None,
            "caffeine_evening": record.caffeine_evening is None,
            "alcohol_evening": record.alcohol_evening is None,
            "exercise": record.exercise is None,
            "notes": record.notes is None,
        }
        features.append(record)
    return features
