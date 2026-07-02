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
        sleep_efficiencies: list[float] = []
        heart_rates: list[float] = []
        resting_rates: list[float] = []
        steps = 0
        activity_minutes = 0.0

        for event in day_events:
            value = event.value_json
            if event.data_type == "sleep":
                if value.get("duration_minutes") is not None:
                    sleep_minutes.append(float(value["duration_minutes"]))
                if value.get("sleep_efficiency") is not None:
                    sleep_efficiencies.append(float(value["sleep_efficiency"]))
            elif event.data_type == "heart_rate":
                if value.get("bpm") is not None:
                    heart_rates.append(float(value["bpm"]))
                if value.get("resting_bpm") is not None:
                    resting_rates.append(float(value["resting_bpm"]))
            elif event.data_type == "steps":
                steps += int(value.get("count") or 0)
            elif event.data_type == "activity":
                activity_minutes += float(value.get("duration_minutes") or 0)

        record = DailyFeature(
            user_id=user_id,
            date=day,
            sleep_duration_minutes=sum(sleep_minutes) if sleep_minutes else None,
            sleep_efficiency=(sum(sleep_efficiencies) / len(sleep_efficiencies)) if sleep_efficiencies else None,
            resting_heart_rate=(sum(resting_rates) / len(resting_rates)) if resting_rates else None,
            mean_heart_rate=(sum(heart_rates) / len(heart_rates)) if heart_rates else None,
            step_count=steps if steps else None,
            activity_minutes=activity_minutes if activity_minutes else None,
        )
        record.missing_mask_json = {
            "sleep_duration_minutes": record.sleep_duration_minutes is None,
            "sleep_efficiency": record.sleep_efficiency is None,
            "resting_heart_rate": record.resting_heart_rate is None,
            "mean_heart_rate": record.mean_heart_rate is None,
            "step_count": record.step_count is None,
            "activity_minutes": record.activity_minutes is None,
        }
        features.append(record)
    return features
