from typing import Literal

from pydantic import BaseModel, Field


AgentMode = Literal["trend", "guide", "question", "auto"]
AgentIntent = Literal["trend_analysis", "education_guidance", "symptom_qa", "referral_escalation"]
ToolName = Literal[
    "analyze_sleep_trends",
    "screen_rls",
    "detect_red_flags",
    "select_templates",
    "retrieve_knowledge",
    "enforce_guardrails",
    "call_external_explanation_model",
]


class SleepAgentRequest(BaseModel):
    mode: AgentMode = "question"
    question: str | None = Field(default=None, max_length=1200)
    include_latest_data: bool = True
    allow_external_model: bool = False


class SleepTrendSummary(BaseModel):
    avg_sleep_7d: float | None = None
    avg_sleep_prev_7d: float | None = None
    sleep_duration_change: float | None = None
    avg_sleep_efficiency_7d: float | None = None
    bedtime_variability_minutes: float | None = None
    wake_time_variability_minutes: float | None = None
    night_awakenings_change: float | None = None
    rls_symptom_nights: int = 0
    short_sleep_flag: bool = False
    irregular_schedule_flag: bool = False
    possible_rls_pattern_flag: bool = False
    possible_osa_warning_flag: bool = False
    latest_sleep_duration_minutes: float | None = None
    latest_sleep_efficiency: float | None = None
    latest_resting_heart_rate: float | None = None
    latest_mean_heart_rate: float | None = None
    latest_step_count: int | None = None
    latest_activity_minutes: float | None = None
    risk_flags: list[str] = Field(default_factory=list)


class EducationPrescription(BaseModel):
    template_id: str
    category: str
    text: str


class KnowledgeSnippet(BaseModel):
    source: str
    intended_use: str
    snippet: str


class RlsScreeningResult(BaseModel):
    status: str
    explanation: str
    matched_features: list[str] = Field(default_factory=list)
    should_seek_care: bool = False


class AgentPlan(BaseModel):
    intent: AgentIntent
    rationale: str
    tool_sequence: list[ToolName] = Field(default_factory=list)
    hitl_required: bool = False
    topic: str = "general"


class ToolExecution(BaseModel):
    tool_name: ToolName
    status: Literal["completed", "skipped"]
    summary: str


class SleepAgentResponse(BaseModel):
    mode: AgentMode
    provider: str
    planner_provider: str = "local-rule-planner"
    hitl_required: bool = False
    answer: str
    plan: AgentPlan | None = None
    tool_trace: list[ToolExecution] = Field(default_factory=list)
    trend_summary: SleepTrendSummary | None = None
    selected_templates: list[EducationPrescription] = Field(default_factory=list)
    knowledge_snippets: list[KnowledgeSnippet] = Field(default_factory=list)
    guide_points: list[str]
    safety_limits: list[str]
    escalation_signals: list[str]
    data_used: list[str]
    red_flags: list[str] = Field(default_factory=list)
    rls_screening: RlsScreeningResult | None = None
    knowledge_sources: list[str] = Field(default_factory=list)
    external_model_used: bool = False
    external_model_error: str | None = None
