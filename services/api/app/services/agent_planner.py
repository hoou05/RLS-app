from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.request
from typing import Any

import certifi
from app.agent.safety import load_safety_rules
from app.core.config import Settings
from app.schemas.agent import AgentPlan


AVAILABLE_TOOLS = [
    "analyze_sleep_trends",
    "screen_rls",
    "detect_red_flags",
    "select_templates",
    "retrieve_knowledge",
    "enforce_guardrails",
]

PLANNER_BOUNDARY = (
    "Planning can use the user's current question plus structured sleep summaries, screening summaries, and safety flags. "
    "It must not use raw wearable events, free-text notes, or raw questionnaire payloads."
)


def build_agent_plan(
    mode: str,
    question: str,
    topic: str,
    trend_summary,
    rls_result,
    red_flags: list[str],
    allow_external_model: bool,
    settings: Settings,
) -> tuple[AgentPlan, str]:
    if allow_external_model and _can_use_deepseek(settings):
        plan = _call_deepseek_planner(mode, question, topic, trend_summary, rls_result, red_flags, settings)
        if plan:
            return plan, settings.deepseek_model
    return _rule_plan(mode, question, topic, trend_summary, rls_result, red_flags), "local-rule-planner"


def _rule_plan(mode: str, question: str, topic: str, trend_summary, rls_result, red_flags: list[str]) -> AgentPlan:
    if any(flag.startswith("unsafe_") for flag in red_flags):
        return AgentPlan(
            intent="referral_escalation",
            rationale="The user is asking for diagnosis, medication, dosing, iron, device, or CPAP-setting guidance, so safety boundaries and referral language must come first.",
            tool_sequence=["detect_red_flags", "retrieve_knowledge", "select_templates", "enforce_guardrails"],
            hitl_required=True,
            topic=topic,
        )
    if mode == "trend":
        return AgentPlan(
            intent="trend_analysis",
            rationale="The request is explicitly for trend review, so the response should prioritize deterministic sleep-summary tools and educational follow-up.",
            tool_sequence=["analyze_sleep_trends", "detect_red_flags", "select_templates", "retrieve_knowledge", "enforce_guardrails"],
            hitl_required=bool(red_flags),
            topic=topic,
        )
    if red_flags:
        return AgentPlan(
            intent="referral_escalation",
            rationale="Red-flag symptoms or contexts are present, so referral-oriented education should take priority over exploratory guidance alone.",
            tool_sequence=["detect_red_flags", "retrieve_knowledge", "select_templates", "enforce_guardrails"],
            hitl_required=True,
            topic=topic,
        )
    if topic == "rls" or (rls_result and rls_result.status != "unlikely_rls_pattern"):
        return AgentPlan(
            intent="symptom_qa",
            rationale="The question maps to RLS-like symptoms, so educational screening plus template and knowledge retrieval are appropriate.",
            tool_sequence=["screen_rls", "retrieve_knowledge", "select_templates", "enforce_guardrails"],
            hitl_required=bool(rls_result and rls_result.should_seek_care),
            topic="rls",
        )
    if mode == "guide":
        return AgentPlan(
            intent="education_guidance",
            rationale="The request is for general sleep guidance, so the system should prefer template-driven education and supportive knowledge snippets.",
            tool_sequence=["analyze_sleep_trends", "select_templates", "retrieve_knowledge", "enforce_guardrails"],
            hitl_required=False,
            topic=topic,
        )
    return AgentPlan(
        intent="symptom_qa",
        rationale="The question is best handled by routing to education templates and topic-specific knowledge before generating an answer.",
        tool_sequence=["detect_red_flags", "retrieve_knowledge", "select_templates", "enforce_guardrails"],
        hitl_required=bool(red_flags),
        topic=topic,
    )


def _can_use_deepseek(settings: Settings) -> bool:
    return (
        settings.sleep_agent_provider.lower() == "deepseek"
        and bool(settings.deepseek_api_key)
        and settings.deepseek_allow_structured_summary
    )


def _call_deepseek_planner(mode: str, question: str, topic: str, trend_summary, rls_result, red_flags: list[str], settings: Settings) -> AgentPlan | None:
    prompt = {
        "task": "Return a JSON plan for a sleep-health education agent.",
        "mode": mode,
        "question": question,
        "topic": topic,
        "trend_summary": trend_summary.model_dump() if trend_summary else None,
        "rls_screening": rls_result.model_dump() if rls_result else None,
        "red_flags": red_flags,
        "available_tools": AVAILABLE_TOOLS,
        "boundary": PLANNER_BOUNDARY,
        "allowed_outputs": load_safety_rules()["allowed_outputs"],
        "response_schema": {
            "intent": "trend_analysis | education_guidance | symptom_qa | referral_escalation",
            "rationale": "short reason",
            "tool_sequence": AVAILABLE_TOOLS,
            "hitl_required": "boolean",
            "topic": "rls | insomnia | osa | general",
        },
    }
    request_body = json.dumps(
        {
            "model": settings.deepseek_model,
            "messages": [
                {"role": "system", "content": "You are a planner for a sleep-health education agent. Return valid JSON only."},
                {"role": "user", "content": json.dumps(prompt)},
            ],
            "stream": False,
            "response_format": {"type": "json_object"},
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
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None
    choices = body.get("choices") or []
    if not choices:
        return None
    content = (choices[0].get("message") or {}).get("content")
    if not isinstance(content, str):
        return None
    try:
        data = json.loads(content)
        return AgentPlan.model_validate(data)
    except (json.JSONDecodeError, ValueError):
        return None


def _deepseek_ssl_context() -> ssl.SSLContext:
    return ssl.create_default_context(cafile=certifi.where())
