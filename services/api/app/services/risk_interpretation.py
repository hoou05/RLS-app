from app.schemas.prediction import DISCLAIMER_TEXT


def risk_level(score: float) -> str:
    if score >= 0.67:
        return "high"
    if score >= 0.34:
        return "moderate"
    return "low"


def recommendation_for(level: str) -> str:
    if level == "high":
        return (
            "Your screening result suggests a higher risk pattern. This is not a diagnosis; "
            "consider discussing persistent symptoms with a clinician."
        )
    if level == "moderate":
        return (
            "Your screening result suggests an intermediate risk pattern. Consider tracking "
            "sleep and symptom patterns and consulting a clinician if symptoms persist."
        )
    return (
        "Your screening result suggests a lower risk pattern based on the available data. "
        "Continue tracking symptoms if they concern you."
    )


def disclaimer() -> str:
    return DISCLAIMER_TEXT
