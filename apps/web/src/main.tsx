import React, { useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { Activity, ArrowRight, ClipboardList, Database, HeartPulse, Info, LineChart, LucideIcon, Moon, ShieldCheck, Upload } from "lucide-react";
import "./styles.css";

const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000";

type Tab = "dashboard" | "predictions" | "questionnaires" | "upload" | "model";
type Screen = "login" | "register" | "app";
type ApiState = { token?: string; latest?: any; predictions: any[]; questionnaires: any[]; features: any[] };
type MessageKind = "info" | "success" | "error";
const navItems: Array<[Tab, LucideIcon, string]> = [
  ["dashboard", Activity, "Dashboard"],
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
  if (response.status === 0) return "Cannot reach the backend. Make sure FastAPI is running on http://localhost:8000.";
  return `HTTP ${response.status}: ${detail}`;
}

function labelForAction(action: string) {
  const labels: Record<string, string> = {
    register: "Registering",
    login: "Logging in",
    sync: "Syncing mock health data",
    predict: "Submitting questionnaire and running prediction",
    refresh: "Refreshing dashboard",
  };
  return labels[action] ?? "Working";
}

createRoot(document.getElementById("root")!).render(<App />);
