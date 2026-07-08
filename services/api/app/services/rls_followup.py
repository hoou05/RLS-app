from __future__ import annotations

from app.schemas.agent import RlsFollowUpQuestion


RLS_FOLLOW_UP_CRITERIA = [
    (
        "urge_to_move",
        "When the discomfort appears, do you feel a strong urge to move your legs, with or without unpleasant sensations?",
        "RLS screening starts by clarifying whether an urge to move is present, not only pain or numbness.",
    ),
    (
        "worse_at_rest",
        "Does it begin or get worse when you are resting, sitting, or lying still?",
        "Symptoms that are provoked by rest fit the educational RLS pattern more than symptoms caused only by activity or injury.",
    ),
    (
        "relieved_by_movement",
        "Does walking, stretching, or moving the legs partly or fully relieve the feeling while you keep moving?",
        "Temporary relief with movement is one of the core RLS screening features.",
    ),
    (
        "evening_or_night",
        "Is it clearly worse in the evening or at night than earlier in the day?",
        "An evening or night pattern helps separate RLS-style symptoms from several daytime discomfort patterns.",
    ),
    (
        "not_better_explained",
        "Could cramps, positional discomfort, swelling, neuropathy, joint pain, medication changes, or another condition explain it better?",
        "RLS should not be concluded when another medical or behavioral explanation is more likely.",
    ),
]


def build_rls_follow_up_questions(question: str, matched_features: list[str]) -> list[RlsFollowUpQuestion]:
    normalized = question.lower()
    answered_terms = set(matched_features)
    if any(term in normalized for term in ["move", "urge", "动腿", "想动"]):
        answered_terms.add("urge_to_move")
    if any(term in normalized for term in ["rest", "sitting", "lying", "休息", "躺"]):
        answered_terms.add("worse_at_rest")
    if any(term in normalized for term in ["relief", "relieve", "walk", "stretch", "走动", "缓解"]):
        answered_terms.add("relieved_by_movement")
    if any(term in normalized for term in ["night", "evening", "晚上", "夜里"]):
        answered_terms.add("evening_or_night")

    return [
        RlsFollowUpQuestion(
            criterion=criterion,
            question=question_text,
            why_it_matters=why_it_matters,
            answered=criterion in answered_terms,
        )
        for criterion, question_text, why_it_matters in RLS_FOLLOW_UP_CRITERIA
    ]
