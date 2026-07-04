from __future__ import annotations

from app.schemas.agent import RlsScreeningResult


def screen_rls(questionnaire: dict | None) -> RlsScreeningResult | None:
    if not questionnaire:
        return None

    feature_map = {
        "urge_to_move_legs": "urge to move the legs or leg discomfort",
        "worse_at_rest": "worse during rest",
        "relieved_by_movement": "relieved by movement",
        "worse_in_evening_or_night": "worse in the evening or night",
    }
    matched = [label for key, label in feature_map.items() if int(questionnaire.get(key, 0) or 0) >= 2]
    impacts_sleep = int(questionnaire.get("sleep_disturbance_score", 0) or 0) >= 5

    if len(matched) >= 4:
        explanation = (
            "The questionnaire pattern may fit RLS features and would be reasonable to discuss with a clinician for further assessment. "
            "This is educational screening only and not a diagnosis."
        )
        return RlsScreeningResult(
            status="possible_rls_pattern",
            explanation=explanation,
            matched_features=matched,
            should_seek_care=impacts_sleep or int(questionnaire.get("symptom_severity", 0) or 0) >= 6,
        )
    if matched:
        return RlsScreeningResult(
            status="partial_rls_features",
            explanation="Some RLS-like features are present, but the pattern is incomplete and other causes remain possible.",
            matched_features=matched,
            should_seek_care=impacts_sleep,
        )
    return RlsScreeningResult(
        status="unlikely_rls_pattern",
        explanation="The recorded answers do not clearly match the typical RLS feature pattern, so other explanations should remain on the table.",
        matched_features=[],
        should_seek_care=impacts_sleep,
    )
