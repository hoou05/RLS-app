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
from app.schemas.agent import EducationPrescription, HealthEducationPrescription, PersonalBaseline, SleepAgentAnswerSections, SleepAgentRequest, SleepAgentResponse, ToolExecution
from app.services.agent_planner import PLANNER_BOUNDARY, build_agent_plan
from app.services.education_library import select_templates
from app.services.knowledge_base import retrieve_knowledge
from app.services.rls_followup import build_rls_follow_up_questions
from app.services.rls_screening import screen_rls
from app.services.sleep_trend_analyzer import analyze_sleep_trends
from app.services.user_memory import build_personal_baseline, memory_to_read, refresh_memory_baseline

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
    "knowledge_base/safety/health_education_prescription_format.md",
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
    rls_followups = build_rls_follow_up_questions(payload.question or "", rls_result.matched_features if rls_result else [])
    personal_baseline = build_personal_baseline(context.features)
    memory = refresh_memory_baseline(session, user.id, context.features) if user.id is not None else None
    user_memory = memory_to_read(memory)
    tool_trace = _execute_tool_trace(plan, trend_summary, rls_result, red_flags, templates, knowledge_snippets, rls_followups, personal_baseline)
    answer_sections = _compose_answer_sections(
        payload,
        trend_summary,
        templates,
        plan.topic,
        rls_result,
        red_flags,
        knowledge_snippets,
        plan.hitl_required,
        rls_followups,
        personal_baseline,
        user_memory.avoid_repeating,
    )
    education_prescription = _build_health_education_prescription(
        topic,
        trend_summary,
        answer_sections,
        rls_result,
        red_flags,
        rls_followups,
        personal_baseline,
    )
    local_answer = enforce_guardrails(_sections_to_answer(answer_sections))
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
        answer_sections=answer_sections,
        education_prescription=education_prescription,
        rls_follow_up_questions=rls_followups if plan.topic == "rls" else [],
        personal_baseline=personal_baseline,
        user_memory=user_memory,
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


def _compose_answer_sections(
    payload: SleepAgentRequest,
    trend_summary,
    templates: list[EducationPrescription],
    topic: str,
    rls_result,
    red_flags: list[str],
    knowledge_snippets,
    hitl_required: bool,
    rls_followups,
    personal_baseline: PersonalBaseline,
    avoid_repeating: list[str],
) -> SleepAgentAnswerSections:
    if is_forbidden_request(red_flags):
        return SleepAgentAnswerSections(
            trend_observation=_trend_observation(trend_summary, personal_baseline),
            interpretation="This question asks for individualized diagnosis or treatment decisions, so the safe interpretation is that a clinician should review the situation.",
            low_risk_suggestions=[
                "Track symptom timing, triggers, sleep disruption, and any medication or device-related concerns to discuss with a clinician.",
                "Avoid changing medication, iron treatment, device settings, or treatment devices based only on this app.",
            ],
            follow_up_questions=_question_texts(rls_followups) if topic == "rls" else ["What symptoms are most disruptive, and how often are they affecting sleep or daytime function?"],
            care_boundary=forbidden_request_response(),
        )

    interpretation_by_topic = {
        "rls": (
            "Your description includes features that can be seen with Restless Legs Syndrome, especially if discomfort appears at rest, worsens in the evening, and improves after movement. "
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
    interpretation = interpretation_by_topic
    if rls_result and topic == "rls":
        interpretation = f"{interpretation} {rls_result.explanation}"
    suggestions = _low_risk_suggestions(topic, templates, avoid_repeating)
    followups = _follow_up_questions(topic, payload.question or "", rls_followups)
    boundary = _care_boundary(red_flags, hitl_required)
    return SleepAgentAnswerSections(
        trend_observation=_trend_observation(trend_summary, personal_baseline),
        interpretation=interpretation,
        low_risk_suggestions=suggestions,
        follow_up_questions=followups,
        care_boundary=boundary,
    )


def _sections_to_answer(sections: SleepAgentAnswerSections) -> str:
    suggestion_text = " ".join(f"- {item}" for item in sections.low_risk_suggestions)
    question_text = " ".join(f"- {item}" for item in sections.follow_up_questions)
    return (
        f"Trend observation: {sections.trend_observation} "
        f"What it may mean: {sections.interpretation} "
        f"Low-risk next steps: {suggestion_text} "
        f"Follow-up questions: {question_text} "
        f"Care boundary: {sections.care_boundary}"
    )


def _trend_observation(trend_summary, baseline: PersonalBaseline) -> str:
    if trend_summary.avg_sleep_7d is None:
        return "There is not enough recent sleep data yet to compare this week with your prior pattern."
    parts = [f"Your recent 7-day average sleep duration is {trend_summary.avg_sleep_7d:.0f} minutes."]
    if trend_summary.avg_sleep_prev_7d is not None and trend_summary.sleep_duration_change is not None:
        direction = "lower" if trend_summary.sleep_duration_change < 0 else "higher"
        parts.append(f"That is {abs(trend_summary.sleep_duration_change):.0f} minutes {direction} than the prior 7-day window.")
    if baseline.usual_sleep_minutes is not None and baseline.data_days >= 7:
        delta = trend_summary.avg_sleep_7d - baseline.usual_sleep_minutes
        parts.append(f"Compared with your {baseline.data_days}-day personal baseline, this is {abs(delta):.0f} minutes {'below' if delta < 0 else 'above'} your usual level.")
    if trend_summary.irregular_schedule_flag:
        parts.append("Your recent bed or wake times look more variable than ideal.")
    if trend_summary.rls_symptom_nights:
        parts.append(f"RLS-style symptoms were recorded on {trend_summary.rls_symptom_nights} recent night(s).")
    return " ".join(parts)


def _low_risk_suggestions(topic: str, templates: list[EducationPrescription], avoid_repeating: list[str]) -> list[str]:
    suggestions = [item.text for item in templates if item.text not in avoid_repeating][:3]
    if suggestions:
        return suggestions
    fallback = {
        "rls": [
            "Keep a symptom log with timing, rest, movement relief, and evening pattern.",
            "Use gentle stretching or a quiet wind-down routine as comfort-focused support.",
        ],
        "insomnia": [
            "Keep wake time consistent and reduce late-evening light, caffeine, and alcohol.",
            "Use the bed mainly for sleep and a calm wind-down routine.",
        ],
        "osa": [
            "Track snoring, choking awakenings, morning headaches, and daytime sleepiness patterns.",
            "Avoid alcohol close to bedtime when snoring or fragmented sleep is present.",
        ],
        "general": [
            "Keep a consistent wake time and a steady sleep window.",
            "Track sleep duration, bedtime, wake time, caffeine, alcohol, activity, and symptoms.",
        ],
    }
    return fallback[topic]


def _follow_up_questions(topic: str, question: str, rls_followups) -> list[str]:
    if topic == "rls":
        return _question_texts(rls_followups)
    if topic == "osa":
        return [
            "Has anyone witnessed breathing pauses, choking, or gasping during sleep?",
            "How often do you feel sleepy during driving, work, school, or conversations?",
            "Do you wake with morning headaches or very dry mouth?",
        ]
    if topic == "insomnia":
        return [
            "Is the main issue falling asleep, staying asleep, waking too early, or feeling unrefreshed?",
            "How many nights per week does this happen, and for how many weeks?",
            "What time do you usually get into bed and get out of bed?",
        ]
    return [
        "What changed recently in schedule, caffeine or alcohol, stress, exercise, travel, or medications?",
        "Which symptom is most disruptive: short sleep, awakenings, leg discomfort, snoring, or daytime sleepiness?",
    ]


def _question_texts(rls_followups) -> list[str]:
    return [item.question for item in rls_followups]


def _care_boundary(red_flags: list[str], hitl_required: bool) -> str:
    if hitl_required or red_flags:
        return "Because this pattern includes safety or referral signals, use this as education only and prioritize clinician or sleep-specialist review for individualized decisions."
    return "This is education and trend observation only; seek clinician review if symptoms persist, worsen, impair daytime function, involve breathing pauses, pregnancy, kidney disease, anemia, neurologic symptoms, or medication/device questions."


def _build_health_education_prescription(
    topic: str,
    trend_summary,
    sections: SleepAgentAnswerSections,
    rls_result,
    red_flags: list[str],
    rls_followups,
    baseline: PersonalBaseline,
) -> HealthEducationPrescription:
    names = {
        "rls": "Possible RLS-style sleep discomfort",
        "osa": "Possible sleep-breathing warning signs",
        "insomnia": "Insomnia-style sleep difficulty",
        "general": "General sleep-health trend",
    }
    symptoms = {
        "rls": [
            "Urge to move the legs or uncomfortable leg sensations",
            "Symptoms during rest or inactivity",
            "Partial or complete relief with movement",
            "Evening or night predominance",
            "Possible mimics such as cramps, neuropathy, joint pain, venous discomfort, or medication-related restlessness",
        ],
        "osa": [
            "Loud or frequent snoring",
            "Witnessed breathing pauses, choking, or gasping awakenings",
            "Morning headaches, dry mouth, or marked daytime sleepiness",
        ],
        "insomnia": [
            "Difficulty falling asleep",
            "Frequent awakenings or early-morning awakening",
            "Unrefreshing sleep and daytime impairment",
        ],
        "general": [
            "Sleep duration, sleep efficiency, bed time, wake time, awakenings, daytime sleepiness, and symptom timing",
        ],
    }
    risk_factors = [
        "Short or irregular sleep schedule" if trend_summary.short_sleep_flag or trend_summary.irregular_schedule_flag else "Recent schedule, caffeine, alcohol, activity, stress, and symptom changes",
        "Persistent sleep disruption or daytime functional impairment",
    ]
    if "possible_osa_warning" in red_flags or trend_summary.possible_osa_warning_flag:
        risk_factors.append("Snoring, choking awakenings, breathing pauses, or marked daytime sleepiness")
    if "medical_comorbidity" in red_flags:
        risk_factors.append("Kidney disease, anemia, neuropathy, or other medical comorbidity")
    if "pregnancy_or_child" in red_flags:
        risk_factors.append("Pregnancy or childhood symptoms")
    if rls_result and topic == "rls":
        risk_factors.append("RLS mimics or secondary contributors should be reviewed by a clinician when symptoms persist")

    other_guidance = [
        f"Personal baseline confidence is {baseline.confidence} based on {baseline.data_days} day(s) of available data.",
        "Bring symptom timing, sleep logs, medication/device questions, and relevant medical history to a clinician if follow-up is needed.",
    ]
    if topic == "rls":
        unanswered = [item.question for item in rls_followups if not item.answered]
        other_guidance.extend(unanswered[:2])

    return HealthEducationPrescription(
        title=f"RLS Screen - {names[topic]} health education prescription",
        target_user="Current app user; educational guidance based on available structured sleep data and current question.",
        health_problem=names[topic],
        brief_summary=sections.interpretation,
        key_symptoms_to_track=symptoms[topic],
        risk_factors_to_review=risk_factors,
        guidance_items=sections.low_risk_suggestions,
        other_guidance=other_guidance,
        use_instructions="Use with symptom tracking and, when needed, clinician review. This educational prescription does not replace medical diagnosis, treatment, or a clinician-issued medical prescription.",
        safety_scope="Allowed: education, trend observation, symptom tracking, low-risk lifestyle support, and referral guidance. Not allowed: diagnosis, medication choice or dosing, iron treatment instructions, CPAP/device settings, or device purchase recommendations.",
    )


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


def _execute_tool_trace(plan, trend_summary, rls_result, red_flags, templates, knowledge_snippets, rls_followups, personal_baseline) -> list[ToolExecution]:
    trace: list[ToolExecution] = []
    for tool_name in plan.tool_sequence:
        summary = {
            "analyze_sleep_trends": f"Generated risk flags: {', '.join(trend_summary.risk_flags) or 'none'}.",
            "screen_rls": rls_result.explanation if rls_result else "No questionnaire was available for RLS educational screening.",
            "detect_red_flags": f"Detected red flags: {', '.join(red_flags) or 'none'}.",
            "ask_rls_followup_questions": f"Prepared {len(rls_followups)} RLS follow-up question(s) across the five core educational screening criteria.",
            "select_templates": f"Selected {len(templates)} education template(s).",
            "retrieve_knowledge": f"Retrieved {len(knowledge_snippets)} knowledge snippet(s).",
            "personalize_with_memory": f"Built a {personal_baseline.confidence}-confidence personal baseline from {personal_baseline.data_days} day(s).",
            "enforce_guardrails": "Applied output boundary checks for diagnosis, medication, iron, device, and CPAP advice.",
        }.get(tool_name, "Executed.")
        trace.append(ToolExecution(tool_name=tool_name, status="completed", summary=summary))
    return trace
