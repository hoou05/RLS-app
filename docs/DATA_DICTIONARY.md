# Data Dictionary

## Wearable Features

- `sleep_duration_minutes`: total sleep time in minutes for a day.
- `sleep_efficiency`: percent of time asleep during the sleep window.
- `resting_heart_rate`: resting heart rate in beats per minute.
- `mean_heart_rate`: mean heart rate in beats per minute.
- `min_heart_rate`: optional minimum heart rate for real-model heart-rate deltas.
- `max_heart_rate`: optional maximum heart rate for real-model heart-rate deltas.
- `step_count`: daily step total.
- `activity_minutes`: daily active minutes.
- `height`: optional height in cm, used by the real model adapter when available.
- `weight`: optional weight in kg, used by the real model adapter when available.
- `experiment_features`: optional escape hatch for exact `rls-prediction-experiments` feature names.
- `missing_mask_json`: field-to-boolean map where `true` means missing.

## Questionnaire Fields

- `urge_to_move_legs`: 0-4.
- `worse_at_rest`: 0-4.
- `relieved_by_movement`: 0-4.
- `worse_in_evening_or_night`: 0-4.
- `sleep_disturbance_score`: 0-10.
- `symptom_frequency`: 0-7 days.
- `symptom_severity`: 0-10.
- `family_history_rls`: optional legacy model field.
- `diabetes`: optional legacy model field.
- `psychiatric_medication`: optional legacy model field.
- `non_leg_symptoms`: optional legacy model field.

## Prediction Fields

- `risk_score`: float from 0 to 1.
- `risk_level`: `low`, `moderate`, or `high`.
- `model_version`: required version string for every prediction.
- `explanation_json`: model mode, tier, feature schema, and signal summary.
- `recommendation_text`: non-diagnostic next-step language.
- `disclaimer_text`: screening-only language.
