from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

import certifi
from sqlmodel import Session, select

from app.agent.safety import detect_red_flags, enforce_guardrails, forbidden_request_response, is_forbidden_request, load_safety_rules
from app.core.config import Settings
from app.db.models import DailyFeature, QuestionnaireResponse, User
from app.schemas.agent import EducationPrescription, SleepAgentRequest, SleepAgentResponse, ToolExecution
from app.services.agent_planner import PLANNER_BOUNDARY, build_agent_plan
from app.services.education_library import select_templates
from app.services.knowledge_base import retrieve_knowledge
from app.services.rls_screening import screen_rls
from app.services.sleep_trend_analyzer import analyze_sleep_trends

SAFETY_LIMITS = [
    "The agent can support sleep trend analysis, education, symptom tracking, and guidance on when to seek clinical care.",
    "It cannot diagnose disease, prescribe medication, suggest iron supplementation, or change medication/device settings.",
    "If severe symptoms, breathing pauses, chest pain, neurologic symptoms, pregnancy, childhood symptoms, kidney disease, anemia, or medication concerns are involved, clinical review is recommended.",
]

ESCALATION_SIGNALS = [
    "Severe daytime sleepiness, drowsy driving, witnessed breathing pauses, choking awakenings, or chest pain.",
    "Pregnancy, childhood symptoms, kidney disease, anemia or low ferritin concerns, neuropathy, or medication-related symptom questions.",
    "Rapid worsening, persistent sleep disruption, spreading symptoms beyond the legs, or major daytime functional impairment.",
]

KNOWLEDGE_SOURCES = [
    "knowledge_base/rls/irlssg_2014_diagnostic_criteria.md",
    "knowledge_base/rls/aasm_2025_rls_plmd_guideline.md",
    "knowledge_base/general_sleep/aasm_sleep_hygiene.md",
    "knowledge_base/insomnia/aasm_2021_behavioral_insomnia.md",
    "knowledge_base/osa/aasm_2017_osa_diagnostic_testing.md",
]

STRUCTURED_ONLY_NOTICE = (
    "External model access is limited to structured trend summaries, template selections, screening summaries, and safety flags. "
    "Raw wearable events, raw questionnaires, and free-text sleep notes are excluded."
)


@dataclass
class AgentContext:
    features: list[DailyFeature]
    questionnaire: QuestionnaireResponse | None


def build_sleep_agent_response(
    session: Session,
    user: User,
    payload: SleepAgentRequest,
    settings: Settings,
) -> SleepAgentResponse:
    context = _load_context(session, user.id) if payload.include_latest_data and user.id is not None else AgentContext([], None)
    trend_summary = analyze_sleep_trends(context.features)
    questionnaire_payload = context.questionnaire.response_json if context.questionnaire else None
    rls_result = screen_rls(questionnaire_payload)
    user_notes = [item.notes for item in context.features if item.notes]
    red_flags = detect_red_flags(payload.question or "", user_notes)
    topic = _route_topic(payload.question or "", trend_summary, rls_result)
    plan, planner_provider = build_agent_plan(
        payload.mode,
        payload.question or "",
        topic,
        trend_summary,
        rls_result,
        red_flags,
        payload.allow_external_model,
        settings,
    )
    templates = select_templates(payload.mode, trend_summary, red_flags, plan.topic)
    knowledge_snippets = retrieve_knowledge(plan.topic, red_flags)
    tool_trace = _execute_tool_trace(plan, trend_summary, rls_result, red_flags, templates, knowledge_snippets)
    local_answer = _compose_local_answer(payload, trend_summary, templates, plan.topic, rls_result, red_flags, knowledge_snippets, plan.hitl_required)
    local_answer = enforce_guardrails(local_answer)
    data_used = _data_used(context)

    external_answer = None
    external_model_error = None
    if _should_call_deepseek(payload, settings):
        external_answer, external_model_error = _call_deepseek(
            payload,
            trend_summary,
            templates,
            rls_result,
            red_flags,
            knowledge_snippets,
            plan,
            settings,
        )
        if external_answer:
            external_answer = enforce_guardrails(external_answer)
        if external_model_error:
            tool_trace.append(
                ToolExecution(
                    tool_name="call_external_explanation_model",
                    status="skipped",
                    summary=external_model_error,
                )
            )

    return SleepAgentResponse(
        mode=payload.mode,
        provider=settings.deepseek_model if external_answer else "local-safety-agent",
        planner_provider=planner_provider,
        hitl_required=plan.hitl_required,
        answer=external_answer or local_answer,
        plan=plan,
        tool_trace=tool_trace,
        trend_summary=trend_summary,
        selected_templates=templates,
        knowledge_snippets=knowledge_snippets,
        guide_points=[item.text for item in templates],
        safety_limits=SAFETY_LIMITS,
        escalation_signals=ESCALATION_SIGNALS,
        data_used=data_used,
        red_flags=red_flags,
        rls_screening=rls_result,
        knowledge_sources=KNOWLEDGE_SOURCES,
        external_model_used=external_answer is not None,
        external_model_error=external_model_error,
    )


def _load_context(session: Session, user_id: int) -> AgentContext:
    features = list(
        session.exec(
            select(DailyFeature)
            .where(DailyFeature.user_id == user_id)
            .order_by(DailyFeature.date.desc())
            .limit(14)
        )
    )
    questionnaire = session.exec(
        select(QuestionnaireResponse)
        .where(QuestionnaireResponse.user_id == user_id)
        .order_by(QuestionnaireResponse.submitted_at.desc())
        .limit(1)
    ).first()
    return AgentContext(features=features, questionnaire=questionnaire)


def _route_topic(question: str, trend_summary, rls_result) -> str:
    normalized = question.lower()
    if any(term in normalized for term in ["restless", "rls", "restleg", "leg", "腿", "不宁腿"]):
        return "rls"
    if any(term in normalized for term in ["apnea", "snore", "呼吸", "打鼾"]):
        return "osa"
    if any(term in normalized for term in ["insomnia", "sleep not", "失眠", "睡不着", "入睡"]):
        return "insomnia"
    if trend_summary.possible_rls_pattern_flag or (rls_result and rls_result.status == "possible_rls_pattern"):
        return "rls"
    if trend_summary.possible_osa_warning_flag:
        return "osa"
    return "general"


def _compose_local_answer(
    payload: SleepAgentRequest,
    trend_summary,
    templates: list[EducationPrescription],
    topic: str,
    rls_result,
    red_flags: list[str],
    knowledge_snippets,
    hitl_required: bool,
) -> str:
    if is_forbidden_request(red_flags):
        parts = [forbidden_request_response()]
        if red_flags:
            parts.append("Because this question crosses a medical safety boundary, clinician review is the right next step for individualized decisions.")
        parts.extend(item.text for item in templates[:1])
        return " ".join(parts)

    if payload.mode == "trend":
        parts = []
        if trend_summary.avg_sleep_7d is None:
            parts.append("There is not enough recent sleep data to compare the last 7 days with the prior week yet.")
        else:
            parts.append(
                f"Over the last 7 days, average sleep duration was {trend_summary.avg_sleep_7d:.1f} minutes"
                + (
                    f", versus {trend_summary.avg_sleep_prev_7d:.1f} minutes in the prior 7-day window."
                    if trend_summary.avg_sleep_prev_7d is not None
                    else "."
                )
            )
            if trend_summary.sleep_duration_change is not None:
                direction = "decreased" if trend_summary.sleep_duration_change < 0 else "increased"
                parts.append(f"That means sleep duration {direction} by {abs(trend_summary.sleep_duration_change):.1f} minutes.")
            if trend_summary.avg_sleep_efficiency_7d is not None:
                parts.append(f"Average sleep efficiency was {trend_summary.avg_sleep_efficiency_7d:.2f}.")
            if trend_summary.irregular_schedule_flag:
                parts.append("Bedtime or wake-time variability suggests an irregular schedule.")
            if trend_summary.possible_rls_pattern_flag:
                parts.append(f"RLS-style symptoms were recorded on {trend_summary.rls_symptom_nights} nights in the recent week.")
            if trend_summary.possible_osa_warning_flag:
                parts.append("Recent notes or sleepiness scores include features that can justify sleep apnea follow-up.")
        parts.extend(item.text for item in templates[:2])
        if knowledge_snippets:
            parts.append(f"Background reference: {knowledge_snippets[0].snippet}")
        if red_flags:
            parts.append("Because some red-flag signals are present, clinical review is worth prioritizing.")
        if hitl_required:
            parts.append("A human clinical review threshold was reached because the current pattern includes higher-risk features.")
        return " ".join(parts)

    if payload.mode == "guide":
        return " ".join(item.text for item in templates) or (
            "Focus on regular wake time, a steady sleep schedule, evening caffeine/alcohol reduction, daytime exercise, and a cool, quiet, dark sleep environment."
        )

    intro = {
        "rls": (
            "Your description includes features that can be seen with Restless Legs Syndrome, especially if discomfort appears at rest, gets worse in the evening, and improves after movement. "
            "That still does not confirm a diagnosis, because cramps, neuropathy, joint issues, venous problems, medication effects, or sleep loss can overlap."
        ),
        "insomnia": (
            "If you are often struggling to fall asleep, wake too early, or feel unrefreshed, the first step is usually to review schedule regularity, evening stimulation, caffeine, alcohol, stress, and the sleep environment."
        ),
        "osa": (
            "Snoring by itself does not diagnose obstructive sleep apnea, but snoring plus witnessed breathing pauses, choking awakenings, strong daytime sleepiness, or morning headaches deserves medical follow-up."
        ),
        "general": (
            "This agent can help with sleep trend review, symptom tracking, and general education across common sleep concerns, with strongest coverage for RLS, insomnia, and possible sleep apnea warning patterns."
        ),
    }[topic]
    body_parts = [intro]
    if rls_result and topic == "rls":
        body_parts.append(rls_result.explanation)
    body_parts.extend(item.text for item in templates[:3])
    if knowledge_snippets:
        body_parts.append(f"Relevant guidance background: {knowledge_snippets[0].snippet}")
    if red_flags:
        body_parts.append("Because your question or notes include higher-risk features, it would be safer to involve a clinician or sleep specialist soon.")
    if hitl_required:
        body_parts.append("This case crosses the app's human-review boundary, so referral-oriented guidance takes priority over self-management advice.")
    return " ".join(body_parts)


def _data_used(context: AgentContext) -> list[str]:
    used: list[str] = []
    if context.features:
        used.append("daily wearable features and sleep notes")
    if context.questionnaire:
        used.append("latest RLS questionnaire")
    return used or ["no personal health data"]


def _should_call_deepseek(payload: SleepAgentRequest, settings: Settings) -> bool:
    return (
        payload.allow_external_model
        and settings.sleep_agent_provider.lower() == "deepseek"
        and bool(settings.deepseek_api_key)
        and settings.deepseek_allow_structured_summary
    )


def _call_deepseek(payload, trend_summary, templates, rls_result, red_flags, knowledge_snippets, plan, settings: Settings) -> tuple[str | None, str | None]:
    prompt = _build_structured_explanation_prompt(payload, trend_summary, templates, rls_result, red_flags, knowledge_snippets, plan)
    request_body = json.dumps(
        {
            "model": settings.deepseek_model,
            "messages": [
                {"role": "system", "content": "You are a cautious sleep-health education agent for a non-diagnostic screening app."},
                {"role": "user", "content": json.dumps(prompt)},
            ],
            "stream": False,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{settings.deepseek_base_url.rstrip('/')}/chat/completions",
        data=request_body,
        headers={
            "Authorization": f"Bearer {settings.deepseek_api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20, context=_deepseek_ssl_context()) as response:
            body: dict[str, Any] = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        return None, f"DeepSeek HTTP {error.code}: {_compact_error(body)}"
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        return None, f"DeepSeek request failed: {_compact_error(str(error))}"

    choices = body.get("choices") or []
    if not choices:
        return None, "DeepSeek returned no choices."
    message = choices[0].get("message") or {}
    content = message.get("content")
    if isinstance(content, str) and content.strip():
        return content, None
    return None, "DeepSeek returned an empty message."


def _deepseek_ssl_context() -> ssl.SSLContext:
    return ssl.create_default_context(cafile=certifi.where())


def _compact_error(message: str) -> str:
    return " ".join(message.split())[:500]


def _build_structured_explanation_prompt(payload, trend_summary, templates, rls_result, red_flags, knowledge_snippets, plan) -> dict[str, Any]:
    return {
        "mode": payload.mode,
        "question": payload.question,
        "plan": plan.model_dump() if plan else None,
        "trend_summary": trend_summary.model_dump(),
        "selected_templates": [item.model_dump() for item in templates],
        "rls_screening": rls_result.model_dump() if rls_result else None,
        "red_flags": red_flags,
        "knowledge_snippets": [item.model_dump() for item in knowledge_snippets],
        "knowledge_sources": KNOWLEDGE_SOURCES,
        "model_boundary": STRUCTURED_ONLY_NOTICE,
        "planner_boundary": PLANNER_BOUNDARY,
        "instruction": (
            "Rewrite the structured analysis into concise educational sleep-health guidance. "
            "Never diagnose, prescribe, recommend drugs, iron, CPAP settings, or device purchase."
        ),
        "allowed_outputs": load_safety_rules()["allowed_outputs"],
    }


def _execute_tool_trace(plan, trend_summary, rls_result, red_flags, templates, knowledge_snippets) -> list[ToolExecution]:
    trace: list[ToolExecution] = []
    for tool_name in plan.tool_sequence:
        summary = {
            "analyze_sleep_trends": f"Generated risk flags: {', '.join(trend_summary.risk_flags) or 'none'}.",
            "screen_rls": rls_result.explanation if rls_result else "No questionnaire was available for RLS educational screening.",
            "detect_red_flags": f"Detected red flags: {', '.join(red_flags) or 'none'}.",
            "select_templates": f"Selected {len(templates)} education template(s).",
            "retrieve_knowledge": f"Retrieved {len(knowledge_snippets)} knowledge snippet(s).",
            "enforce_guardrails": "Applied output boundary checks for diagnosis, medication, iron, device, and CPAP advice.",
        }.get(tool_name, "Executed.")
        trace.append(ToolExecution(tool_name=tool_name, status="completed", summary=summary))
    return trace
