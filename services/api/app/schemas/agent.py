from typing import Literal

from pydantic import BaseModel, Field


AgentMode = Literal["trend", "guide", "question", "auto"]
AgentIntent = Literal["trend_analysis", "education_guidance", "symptom_qa", "referral_escalation"]
ToolName = Literal[
    "analyze_sleep_trends",
    "screen_rls",
    "detect_red_flags",
    "ask_rls_followup_questions",
    "select_templates",
    "retrieve_knowledge",
    "personalize_with_memory",
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


class RlsFollowUpQuestion(BaseModel):
    criterion: str
    question: str
    why_it_matters: str
    answered: bool = False


class SleepAgentAnswerSections(BaseModel):
    trend_observation: str
    interpretation: str
    low_risk_suggestions: list[str] = Field(default_factory=list)
    follow_up_questions: list[str] = Field(default_factory=list)
    care_boundary: str


class PersonalBaseline(BaseModel):
    usual_sleep_minutes: float | None = None
    usual_sleep_efficiency: float | None = None
    usual_bed_time: str | None = None
    usual_wake_time: str | None = None
    rls_symptom_rate: float | None = None
    data_days: int = 0
    confidence: str = "low"


class UserMemoryRead(BaseModel):
    preferred_language: str | None = None
    preferred_answer_style: str | None = None
    avoid_repeating: list[str] = Field(default_factory=list)
    learned_facts: dict = Field(default_factory=dict)
    feedback_summary: dict = Field(default_factory=dict)


class HealthEducationPrescription(BaseModel):
    title: str
    target_user: str
    health_problem: str
    brief_summary: str
    key_symptoms_to_track: list[str] = Field(default_factory=list)
    risk_factors_to_review: list[str] = Field(default_factory=list)
    guidance_items: list[str] = Field(default_factory=list)
    other_guidance: list[str] = Field(default_factory=list)
    use_instructions: str
    safety_scope: str
    source_format: str = "Health education prescription format: title, target, brief condition summary, symptoms, risk factors, guidance, other guidance, use instructions, and contact/referral boundary."


class AgentFeedbackRequest(BaseModel):
    rating: Literal["helpful", "not_helpful", "too_generic", "too_complex", "already_tried"]
    reason: str | None = Field(default=None, max_length=500)
    question: str | None = Field(default=None, max_length=1200)
    answer_excerpt: str | None = Field(default=None, max_length=1200)
    metadata: dict = Field(default_factory=dict)


class AgentFeedbackResponse(BaseModel):
    status: str
    memory: UserMemoryRead


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
    answer_sections: SleepAgentAnswerSections | None = None
    education_prescription: HealthEducationPrescription | None = None
    rls_follow_up_questions: list[RlsFollowUpQuestion] = Field(default_factory=list)
    personal_baseline: PersonalBaseline | None = None
    user_memory: UserMemoryRead | None = None
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
