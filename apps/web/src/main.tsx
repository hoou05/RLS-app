import React, { useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { Activity, AlertTriangle, ArrowRight, Bot, ClipboardList, Database, HeartPulse, Info, LineChart, LucideIcon, MessageCircle, Moon, Send, ShieldCheck, Upload, X } from "lucide-react";
import "./styles.css";

const API_URL = import.meta.env.VITE_API_URL ?? "http://127.0.0.1:8000";

type Tab = "dashboard" | "agent" | "predictions" | "questionnaires" | "upload" | "model";
type Screen = "login" | "register" | "app";
type ApiState = { token?: string; latest?: any; predictions: any[]; questionnaires: any[]; features: any[] };
type MessageKind = "info" | "success" | "error";
type AgentMode = "trend" | "guide" | "question";
type AgentChatMessage = { role: "user" | "assistant"; text: string; meta?: string };
const navItems: Array<[Tab, LucideIcon, string]> = [
  ["dashboard", Activity, "Dashboard"],
  ["agent", Bot, "Sleep agent"],
  ["predictions", LineChart, "Prediction history"],
  ["questionnaires", ClipboardList, "Questionnaires"],
  ["upload", Upload, "Upload/debug"],
  ["model", Info, "Model info"],
];

function App() {
  const [screen, setScreen] = useState<Screen>("login");
  const [tab, setTab] = useState<Tab>("dashboard");
  const [email, setEmail] = useState("demo@example.com");
  const [password, setPassword] = useState("password123");
  const [age, setAge] = useState("51");
  const [sex, setSex] = useState("female");
  const [height, setHeight] = useState("165");
  const [weight, setWeight] = useState("62");
  const [message, setMessage] = useState("Ready for local MVP testing.");
  const [messageKind, setMessageKind] = useState<MessageKind>("info");
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [state, setState] = useState<ApiState>({ predictions: [], questionnaires: [], features: [] });
  const [agentQuestion, setAgentQuestion] = useState("Could my night leg discomfort be Restleg / RLS?");
  const [agentReply, setAgentReply] = useState<any | null>(null);
  const [agentUseExternal, setAgentUseExternal] = useState(false);
  const [widgetOpen, setWidgetOpen] = useState(false);
  const [chatHistory, setChatHistory] = useState<AgentChatMessage[]>([
    {
      role: "assistant",
      text: "Ask about sleep trends, sleep hygiene, RLS-style symptoms, insomnia, or possible sleep apnea warning signs.",
      meta: "Sleep agent",
    },
  ]);

  const isAuthenticated = Boolean(state.token);
  const authLabel = isAuthenticated ? "Authorized" : "Not signed in";
  const authHeaders = useMemo(() => ({
    "Content-Type": "application/json",
    ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
  }), [state.token]);

  async function api(path: string, options: RequestInit = {}, tokenOverride?: string) {
    const headers = {
      ...authHeaders,
      ...(tokenOverride ? { Authorization: `Bearer ${tokenOverride}` } : {}),
      ...(options.headers || {}),
    };
    let response: Response;
    try {
      response = await fetch(`${API_URL}${path}`, { ...options, headers });
    } catch {
      throw new Error(`Cannot reach the backend at ${API_URL}. Make sure FastAPI is running, then refresh this page.`);
    }
    if (!response.ok) throw new Error(await formatApiError(response));
    return response.json();
  }

  async function enterAppAfterAuth(token: string, successMessage: string) {
    setState((s) => ({ ...s, token }));
    setScreen("app");
    setTab("dashboard");
    try {
      await refresh(token);
      setMessageKind("success");
      setMessage(successMessage);
    } catch (error) {
      setMessageKind("error");
      setMessage(
        `Signed in, but the dashboard refresh failed: ${
          error instanceof Error ? error.message : "Unexpected error."
        }`
      );
    }
  }

  async function register() {
    await runAction("register", async () => {
      const body = {
        email,
        password,
        age: Number(age),
        sex,
        height: Number(height),
        weight: Number(weight),
        consent_version: "mvp-consent-v1",
      };
      const data = await api("/auth/register", { method: "POST", body: JSON.stringify(body) });
      await enterAppAfterAuth(data.access_token, "Registered and signed in. You can now sync mock health data.");
    });
  }

  async function login() {
    await runAction("login", async () => {
      const data = await api("/auth/login", { method: "POST", body: JSON.stringify({ email, password }) });
      await enterAppAfterAuth(data.access_token, "Logged in and refreshed the dashboard.");
    });
  }

  async function syncMockHealthData() {
    await runAction("sync", async () => {
      await api("/wearable/upload", {
        method: "POST",
        body: JSON.stringify({
          events: [
            { source: "mock", data_type: "sleep", start_time: "2026-07-02T00:00:00Z", end_time: "2026-07-02T07:00:00Z", value_json: { duration_minutes: 410, sleep_efficiency: 82 } },
            { source: "mock", data_type: "heart_rate", start_time: "2026-07-02T06:00:00Z", end_time: "2026-07-02T06:10:00Z", value_json: { bpm: 74, resting_bpm: 66 } },
            { source: "mock", data_type: "steps", start_time: "2026-07-02T08:00:00Z", end_time: "2026-07-02T20:00:00Z", value_json: { count: 6200 } },
            { source: "mock", data_type: "activity", start_time: "2026-07-02T18:00:00Z", end_time: "2026-07-02T18:26:00Z", value_json: { duration_minutes: 26 } }
          ],
        }),
      });
      const features = await api("/wearable/daily-features");
      setState((s) => ({ ...s, features }));
      setMessageKind("success");
      setMessage("Mock wearable data synced and daily features refreshed.");
    });
  }

  async function submitQuestionnaireAndPredict() {
    await runAction("predict", async () => {
      await api("/questionnaire/submit", {
        method: "POST",
        body: JSON.stringify({
          urge_to_move_legs: 3,
          worse_at_rest: 3,
          relieved_by_movement: 2,
          worse_in_evening_or_night: 3,
          sleep_disturbance_score: 6,
          symptom_frequency: 4,
          symptom_severity: 5,
        }),
      });
      const latestFeatures = await api("/wearable/daily-features");
      const feature = latestFeatures[0] ?? {};
      setState((s) => ({ ...s, features: latestFeatures }));
      const prediction = await api("/predict/tier2", {
        method: "POST",
        body: JSON.stringify({
          sleep_duration_minutes: feature.sleep_duration_minutes ?? 405,
          sleep_efficiency: feature.sleep_efficiency ?? 80,
          resting_heart_rate: feature.resting_heart_rate ?? 69,
          mean_heart_rate: feature.mean_heart_rate ?? 78,
          step_count: feature.step_count ?? 5200,
          activity_minutes: feature.activity_minutes ?? 26,
          age: 51,
          sex: "female",
          height: 165,
          weight: 62,
          missing_mask_json: feature.missing_mask_json ?? {},
          urge_to_move_legs: 3,
          worse_at_rest: 3,
          relieved_by_movement: 2,
          worse_in_evening_or_night: 3,
          sleep_disturbance_score: 6,
          symptom_frequency: 4,
          symptom_severity: 5,
        }),
      });
      await refresh();
      setState((s) => ({ ...s, latest: prediction }));
      setMessageKind("success");
      setMessage("Tier 2 screening result generated.");
    });
  }

  async function refresh(tokenOverride?: string) {
    const [report, predictions, questionnaires, features] = await Promise.all([
      api("/reports/latest", {}, tokenOverride),
      api("/predictions/history", {}, tokenOverride),
      api("/questionnaire/history", {}, tokenOverride),
      api("/wearable/daily-features", {}, tokenOverride),
    ]);
    setState((s) => ({ ...s, latest: report.latest_prediction, predictions, questionnaires, features }));
  }

  async function refreshFromButton() {
    await runAction("refresh", async () => {
      await refresh();
      setMessageKind("success");
      setMessage("Dashboard refreshed.");
    });
  }

  async function runSleepAgent(mode: AgentMode, surface: "panel" | "widget" = "panel") {
    if (mode === "question" && surface === "widget") {
      setChatHistory((items) => [...items, { role: "user", text: agentQuestion }]);
    }
    await runAction(`agent-${mode}`, async () => {
      const reply = await api("/agent/sleep", {
        method: "POST",
        body: JSON.stringify({
          mode,
          question: mode === "question" ? agentQuestion : undefined,
          include_latest_data: true,
          allow_external_model: agentUseExternal,
        }),
      });
      setAgentReply(reply);
      if (surface === "panel") {
        setTab("agent");
      } else {
        setWidgetOpen(true);
        setChatHistory((items) => [
          ...items,
          {
            role: "assistant",
            text: reply.answer,
            meta: `${reply.provider}${reply.external_model_used ? " • structured explanation layer" : ""}`,
          },
        ]);
      }
      setMessageKind("success");
      setMessage(`Sleep agent answered with ${reply.provider}.`);
    });
  }

  async function runAction(name: string, action: () => Promise<void>) {
    setBusyAction(name);
    setMessageKind("info");
    setMessage(`${labelForAction(name)}...`);
    try {
      await action();
    } catch (error) {
      setMessageKind("error");
      setMessage(error instanceof Error ? error.message : "Unexpected error.");
    } finally {
      setBusyAction(null);
    }
  }

  const latest = state.latest;

  if (screen !== "app") {
    return (
      <AuthScreen
        screen={screen}
        setScreen={setScreen}
        email={email}
        setEmail={setEmail}
        password={password}
        setPassword={setPassword}
        age={age}
        setAge={setAge}
        sex={sex}
        setSex={setSex}
        height={height}
        setHeight={setHeight}
        weight={weight}
        setWeight={setWeight}
        message={message}
        messageKind={messageKind}
        busyAction={busyAction}
        login={login}
        register={register}
      />
    );
  }

  return (
    <main className="app-shell">
      <aside>
        <RlsLogo compact />
        {navItems.map(([key, Icon, label]) => (
          <button className={tab === key ? "active" : ""} onClick={() => setTab(key)} key={key}>
            <Icon size={18} />{label}
          </button>
        ))}
      </aside>
      <section className="workspace">
        <div className="motion-bg" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
        <header className="dashboard-header">
          <div className="title-block">
            <p className="eyebrow">Non-diagnostic screening MVP</p>
            <h1>Restless Legs Syndrome Risk Estimate</h1>
            <p>Track mock wearable signals, questionnaire inputs, and model output in one local testing dashboard.</p>
          </div>
          <div className="session-tools">
            <span className={`auth-state ${isAuthenticated ? "ok" : ""}`}>{authLabel}</span>
            <button onClick={() => setScreen("login")}>Switch account</button>
          </div>
        </header>
        <div className="notice-row">
          <p className="disclaimer">Screening and risk estimate only. This MVP is not a diagnosis and does not determine whether you have RLS.</p>
          <p className={`status ${messageKind}`}>{message}</p>
        </div>

        {tab === "dashboard" && (
          <div className="grid">
            <section className="panel hero risk-panel">
              <div className="risk-topline">
                <span>Latest risk score</span>
                <Moon size={18} />
              </div>
              <strong>{latest?.risk_score ?? "--"}</strong>
              <em>{latest?.risk_level ?? "No screening result yet"}</em>
              <div className="risk-scale">
                <span />
              </div>
            </section>
            <section className="panel quick-panel">
              <h2>Quick flow</h2>
              <div className="actions">
                <button onClick={syncMockHealthData} disabled={!isAuthenticated || busyAction !== null}>{busyAction === "sync" ? "Syncing..." : "Sync mock health data"}</button>
                <button onClick={submitQuestionnaireAndPredict} disabled={!isAuthenticated || busyAction !== null}>{busyAction === "predict" ? "Predicting..." : "Submit questionnaire + predict"}</button>
                <button onClick={refreshFromButton} disabled={!isAuthenticated || busyAction !== null}>{busyAction === "refresh" ? "Refreshing..." : "Refresh"}</button>
              </div>
            </section>
            <Metric title="Sleep" value={`${state.features[0]?.sleep_duration_minutes ?? "--"} min`} caption="Mock nightly duration" />
            <Metric title="Heart rate" value={`${state.features[0]?.mean_heart_rate ?? "--"} bpm`} caption="Daily mean" />
            <Metric title="Steps" value={state.features[0]?.step_count ?? "--"} caption="Mock movement total" />
            <Metric title="Data source" value="Mock" caption="HealthKit / Health Connect TODO" />
          </div>
        )}
        {tab === "agent" && (
          <section className="agent-layout">
            <div className="panel agent-panel">
              <div className="agent-heading">
                <Bot size={24} />
                <div>
                  <h2>Sleep agent debug</h2>
                  <p>Trend review, conservative guidance, and bounded sleep-health Q&A on top of your current structured data.</p>
                </div>
              </div>
              <label className="agent-toggle">
                <input type="checkbox" checked={agentUseExternal} onChange={(event) => setAgentUseExternal(event.target.checked)} />
                <span>Use DeepSeek explanation layer only from structured summaries</span>
              </label>
              <p className="agent-boundary-note">
                When enabled, the backend still sends only trend summaries, selected templates, screening summaries, and safety flags.
              </p>
              <div className="agent-actions">
                <button onClick={() => runSleepAgent("trend")} disabled={!isAuthenticated || busyAction !== null}>
                  Analyze trend
                </button>
                <button onClick={() => runSleepAgent("guide")} disabled={!isAuthenticated || busyAction !== null}>
                  Sleep guide
                </button>
              </div>
              <label className="agent-question">
                Question
                <textarea value={agentQuestion} onChange={(event) => setAgentQuestion(event.target.value)} rows={4} />
              </label>
              <button className="agent-send" onClick={() => runSleepAgent("question")} disabled={!isAuthenticated || busyAction !== null}>
                <Send size={17} />
                {busyAction === "agent-question" ? "Asking..." : "Ask agent"}
              </button>
            </div>
            <div className="panel agent-response">
              <h2>Agent response</h2>
              {agentReply ? (
                <>
                  <p className="agent-answer">{agentReply.answer}</p>
                  <div className="agent-meta">
                    <span>Provider: {agentReply.provider}</span>
                    <span>Planner: {agentReply.planner_provider}</span>
                    <span>HITL: {agentReply.hitl_required ? "yes" : "no"}</span>
                    <span>External model: {agentReply.external_model_used ? "yes" : "no"}</span>
                    <span>Data: {agentReply.data_used?.join(", ")}</span>
                  </div>
                  {agentReply.external_model_error && (
                    <p className="agent-error-note">{agentReply.external_model_error}</p>
                  )}
                  <PlanPanel reply={agentReply} />
                  <TrendSnapshot reply={agentReply} />
                  <TemplateList reply={agentReply} />
                  <ScreeningPanel reply={agentReply} />
                  <FlagPanel title="Red flags" items={agentReply.red_flags} emptyLabel="No immediate red-flag signals surfaced from the current question and notes." />
                  <KnowledgePanel reply={agentReply} />
                  <ToolTracePanel reply={agentReply} />
                  <FlagPanel title="Guide points" items={agentReply.guide_points} emptyLabel="No guide points selected yet." />
                  <h3>Safety limits</h3>
                  <ul>{agentReply.safety_limits?.map((point: string) => <li key={point}>{point}</li>)}</ul>
                  <h3>Knowledge sources</h3>
                  <ul>{agentReply.knowledge_sources?.map((point: string) => <li key={point}>{point}</li>)}</ul>
                </>
              ) : (
                <p className="agent-empty">Run a trend, guide, or question check to see the agent output here.</p>
              )}
            </div>
          </section>
        )}
        {tab === "predictions" && <JsonList title="Prediction history" items={state.predictions} />}
        {tab === "questionnaires" && <JsonList title="Questionnaire history" items={state.questionnaires} />}
        {tab === "upload" && <JsonList title="Latest daily features" items={state.features} />}
        {tab === "model" && (
          <section className="panel prose">
            <Database size={24} />
            <h2>Model information</h2>
            <p>Tier 1 uses wearable-only features. Tier 2 adds questionnaire responses. The MVP attempts to load pickle artifacts and otherwise uses a deterministic fallback score.</p>
            <p>TODO: connect the XGBoost and TabM ensemble exported from rls-prediction-experiments after feature translation and validation.</p>
          </section>
        )}
        <footer className="app-corner">
          <RlsLogo compact />
          <div>
            <span>research-ops@rls-screen.local</span>
            <span>Local MVP logs: browser console + FastAPI terminal</span>
          </div>
        </footer>
        <button className="agent-fab" onClick={() => setWidgetOpen((value) => !value)} aria-label="Open sleep agent">
          {widgetOpen ? <X size={20} /> : <MessageCircle size={20} />}
          <span>Sleep agent</span>
        </button>
        {widgetOpen && (
          <section className="agent-widget panel">
            <div className="agent-widget-header">
              <div>
                <strong>Sleep agent</strong>
                <p>Quick Q&A, trend checks, and safe sleep guidance.</p>
              </div>
              <button className="agent-widget-close" onClick={() => setWidgetOpen(false)} aria-label="Close sleep agent">
                <X size={18} />
              </button>
            </div>
            <label className="agent-toggle compact">
              <input type="checkbox" checked={agentUseExternal} onChange={(event) => setAgentUseExternal(event.target.checked)} />
              <span>DeepSeek explanation layer</span>
            </label>
            <div className="agent-chat-log">
              {chatHistory.map((item, index) => (
                <div className={`agent-bubble ${item.role}`} key={`${item.role}-${index}-${item.text.slice(0, 24)}`}>
                  {item.meta && <small>{item.meta}</small>}
                  <p>{item.text}</p>
                </div>
              ))}
            </div>
            <label className="agent-question compact">
              Ask now
              <textarea value={agentQuestion} onChange={(event) => setAgentQuestion(event.target.value)} rows={3} />
            </label>
            <div className="agent-widget-actions">
              <button onClick={() => runSleepAgent("trend", "widget")} disabled={!isAuthenticated || busyAction !== null}>
                Trend
              </button>
              <button onClick={() => runSleepAgent("question", "widget")} disabled={!isAuthenticated || busyAction !== null}>
                <Send size={16} />
                Ask
              </button>
            </div>
          </section>
        )}
      </section>
    </main>
  );
}

function AuthScreen({
  screen,
  setScreen,
  email,
  setEmail,
  password,
  setPassword,
  age,
  setAge,
  sex,
  setSex,
  height,
  setHeight,
  weight,
  setWeight,
  message,
  messageKind,
  busyAction,
  login,
  register,
}: {
  screen: "login" | "register";
  setScreen: (screen: Screen) => void;
  email: string;
  setEmail: (value: string) => void;
  password: string;
  setPassword: (value: string) => void;
  age: string;
  setAge: (value: string) => void;
  sex: string;
  setSex: (value: string) => void;
  height: string;
  setHeight: (value: string) => void;
  weight: string;
  setWeight: (value: string) => void;
  message: string;
  messageKind: MessageKind;
  busyAction: string | null;
  login: () => Promise<void>;
  register: () => Promise<void>;
}) {
  const isRegister = screen === "register";

  return (
    <main className="auth-page">
      <nav className="auth-nav">
        <RlsLogo compact />
        <div className="auth-nav-center">
          <span>Risk screen</span>
          <span>Wearable sync</span>
          <span>Questionnaire</span>
          <span>Reports</span>
        </div>
        <div className="auth-links">
          <button className={screen === "login" ? "active" : ""} onClick={() => setScreen("login")}>Sign in</button>
          <button className={screen === "register" ? "active outline" : "outline"} onClick={() => setScreen("register")}>Sign up</button>
        </div>
      </nav>
      <section className="auth-hero">
        <p className="auth-kicker">Local non-diagnostic MVP</p>
        <h1>{isRegister ? "Build your screening profile" : "Welcome to your screening dashboard"}</h1>
        <p className="auth-copy">
          {isRegister
            ? "Create a lightweight testing profile, accept the MVP consent note, then continue to wearable sync and screening reports."
            : "Continue testing the wearable upload, questionnaire flow, prediction API, and latest report in one place."}
        </p>
      </section>
      <section className="auth-card">
        <div className="auth-card-header">
          <div className="auth-card-icon"><ShieldCheck size={24} /></div>
          <div>
            <h2>{isRegister ? "Create account" : "Welcome back"}</h2>
            <p>{isRegister ? "Set up a demo profile for local testing." : "Continue to the MVP dashboard."}</p>
          </div>
        </div>
        {isRegister && (
          <div className="steps">
            <span>1 Account</span>
            <span>2 Profile</span>
            <span>3 Consent</span>
          </div>
        )}
        <label>
          Email address
          <input value={email} onChange={(event) => setEmail(event.target.value)} />
        </label>
        <label>
          Password
          <input type="password" value={password} onChange={(event) => setPassword(event.target.value)} />
        </label>
        {isRegister && (
          <>
            <div className="form-grid">
              <label>
                Age
                <input inputMode="numeric" value={age} onChange={(event) => setAge(event.target.value)} />
              </label>
              <label>
                Sex
                <select value={sex} onChange={(event) => setSex(event.target.value)}>
                  <option value="female">Female</option>
                  <option value="male">Male</option>
                  <option value="other">Other</option>
                </select>
              </label>
            </div>
            <div className="form-grid">
              <label>
                Height cm
                <input inputMode="decimal" value={height} onChange={(event) => setHeight(event.target.value)} />
              </label>
              <label>
                Weight kg
                <input inputMode="decimal" value={weight} onChange={(event) => setWeight(event.target.value)} />
              </label>
            </div>
            <p className="mini-consent">By continuing, you accept MVP consent version <strong>mvp-consent-v1</strong>.</p>
          </>
        )}
        <button className="primary-auth" onClick={isRegister ? register : login} disabled={busyAction !== null}>
          <span>{busyAction === "register" ? "Creating account..." : busyAction === "login" ? "Signing in..." : isRegister ? "Create account" : "Sign in"}</span>
          <ArrowRight size={18} />
        </button>
        <p className={`status ${messageKind}`}>{message}</p>
        <p className="switch-copy">
          {isRegister ? "Already have an account?" : "New to this MVP?"}
          <button onClick={() => setScreen(isRegister ? "login" : "register")}>
            {isRegister ? "Sign in" : "Create an account"}
          </button>
        </p>
      </section>
    </main>
  );
}

function RlsLogo({ compact = false }: { compact?: boolean }) {
  return (
    <div className={compact ? "rls-logo compact" : "rls-logo"}>
      <div className="logo-mark">
        <HeartPulse size={20} />
        <span className="leg-line" />
      </div>
      <div>
        <strong>RLS Screen</strong>
        {!compact && <span>Rest-aware screening MVP</span>}
      </div>
    </div>
  );
}

function Metric({ title, value, caption }: { title: string; value: string | number; caption: string }) {
  return (
    <section className="panel metric">
      <span>{title}</span>
      <strong>{value}</strong>
      <em>{caption}</em>
    </section>
  );
}

function JsonList({ title, items }: { title: string; items: any[] }) {
  return <section className="panel wide"><h2>{title}</h2><pre>{JSON.stringify(items, null, 2)}</pre></section>;
}

function PlanPanel({ reply }: { reply: any }) {
  const plan = reply?.plan;
  if (!plan) return null;
  return (
    <div className="agent-plan-card">
      <div className="agent-screening-head">
        <Bot size={18} />
        <div>
          <strong>{plan.intent}</strong>
          <span>{plan.topic} • HITL {plan.hitl_required ? "required" : "not required"}</span>
        </div>
      </div>
      <p>{plan.rationale}</p>
      <FlagPanel title="Planned tools" items={plan.tool_sequence} emptyLabel="No tools were planned." />
    </div>
  );
}

function TrendSnapshot({ reply }: { reply: any }) {
  const trend = reply?.trend_summary;
  if (!trend) return null;
  const minutesOrEmpty = (value: number | null | undefined) => value === null || value === undefined ? "--" : `${value} min`;
  const valueOrEmpty = (value: number | string | null | undefined) => value === null || value === undefined ? "--" : `${value}`;
  const cards = [
    ["Avg sleep 7d", minutesOrEmpty(trend.avg_sleep_7d)],
    ["Prev 7d", minutesOrEmpty(trend.avg_sleep_prev_7d)],
    ["Change", minutesOrEmpty(trend.sleep_duration_change)],
    ["Efficiency 7d", valueOrEmpty(trend.avg_sleep_efficiency_7d)],
    ["Bedtime var", minutesOrEmpty(trend.bedtime_variability_minutes)],
    ["RLS nights", `${trend.rls_symptom_nights ?? 0}`],
  ];
  return (
    <>
      <h3>Trend snapshot</h3>
      <div className="agent-stats-grid">
        {cards.map(([label, value]) => (
          <div className="agent-stat-card" key={label}>
            <small>{label}</small>
            <strong>{value}</strong>
          </div>
        ))}
      </div>
      <FlagPanel title="Risk flags" items={trend.risk_flags} emptyLabel="No sleep-health warning flags were generated from the current 14-day summary." />
    </>
  );
}

function ToolTracePanel({ reply }: { reply: any }) {
  const trace = reply?.tool_trace ?? [];
  if (!trace.length) return null;
  return (
    <>
      <h3>Tool trace</h3>
      <div className="agent-template-list">
        {trace.map((item: any) => (
          <div className="agent-template-card" key={`${item.tool_name}-${item.summary}`}>
            <small>{item.status}</small>
            <strong>{item.tool_name}</strong>
            <p>{item.summary}</p>
          </div>
        ))}
      </div>
    </>
  );
}

function KnowledgePanel({ reply }: { reply: any }) {
  const snippets = reply?.knowledge_snippets ?? [];
  if (!snippets.length) return null;
  return (
    <>
      <h3>Knowledge snippets</h3>
      <div className="agent-template-list">
        {snippets.map((item: any) => (
          <div className="agent-template-card" key={`${item.source}-${item.snippet}`}>
            <small>{item.source}</small>
            <strong>{item.intended_use}</strong>
            <p>{item.snippet}</p>
          </div>
        ))}
      </div>
    </>
  );
}

function TemplateList({ reply }: { reply: any }) {
  const templates = reply?.selected_templates ?? [];
  if (!templates.length) return null;
  return (
    <>
      <h3>Selected education templates</h3>
      <div className="agent-template-list">
        {templates.map((item: any) => (
          <div className="agent-template-card" key={item.template_id}>
            <small>{item.category}</small>
            <strong>{item.template_id}</strong>
            <p>{item.text}</p>
          </div>
        ))}
      </div>
    </>
  );
}

function ScreeningPanel({ reply }: { reply: any }) {
  const screening = reply?.rls_screening;
  if (!screening) return null;
  return (
    <div className="agent-screening-card">
      <div className="agent-screening-head">
        <ClipboardList size={18} />
        <div>
          <strong>RLS educational screening</strong>
          <span>{screening.status}</span>
        </div>
      </div>
      <p>{screening.explanation}</p>
      <FlagPanel title="Matched features" items={screening.matched_features} emptyLabel="No specific RLS-style features were matched." />
    </div>
  );
}

function FlagPanel({ title, items, emptyLabel }: { title: string; items?: string[]; emptyLabel: string }) {
  return (
    <>
      <h3>{title}</h3>
      {items && items.length ? (
        <ul>{items.map((item) => <li key={item}>{item}</li>)}</ul>
      ) : (
        <p className="agent-empty with-icon"><AlertTriangle size={15} />{emptyLabel}</p>
      )}
    </>
  );
}

async function formatApiError(response: Response) {
  let detail = response.statusText;
  try {
    const body = await response.json();
    if (typeof body.detail === "string") {
      detail = body.detail;
    } else if (Array.isArray(body.detail)) {
      detail = body.detail.map((item: any) => `${item.loc?.join(".") ?? "field"}: ${item.msg}`).join("; ");
    } else {
      detail = JSON.stringify(body);
    }
  } catch {
    detail = await response.text();
  }
  if (response.status === 409) return `${detail}. Try Login instead.`;
  if (response.status === 401) return `${detail}. Check your email/password or login again.`;
  if (response.status === 0) return "Cannot reach the backend. Make sure FastAPI is running on http://127.0.0.1:8000.";
  return `HTTP ${response.status}: ${detail}`;
}

function labelForAction(action: string) {
  const labels: Record<string, string> = {
    register: "Registering",
    login: "Logging in",
    sync: "Syncing mock health data",
    predict: "Submitting questionnaire and running prediction",
    refresh: "Refreshing dashboard",
    "agent-trend": "Asking sleep agent for trend analysis",
    "agent-guide": "Asking sleep agent for guide points",
    "agent-question": "Asking sleep agent",
  };
  return labels[action] ?? "Working";
}

createRoot(document.getElementById("root")!).render(<App />);
