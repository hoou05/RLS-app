# Sleep Agent Safety and DeepSeek Notes

This app can expose a sleep-health education agent for local debugging through `POST /agent/sleep`.

## Runtime shape

The current backend uses a hybrid runtime:

- planner
- tool router
- deterministic tools for trend analysis, RLS educational screening, template selection, safety checks, and knowledge retrieval
- optional LLM explanation and planning layer

By default, the planner is local and rule-based. When DeepSeek is enabled, the model can be used for JSON planning and final educational explanation, but still only from structured intermediate outputs.

## Current recommendation

Use the built-in local safety agent by default. It can summarize sleep trends, return conservative sleep-hygiene guide points, and answer bounded symptom questions with emphasis on Restless Legs Syndrome (RLS).

DeepSeek API use should stay optional and disabled for raw sensitive health data unless there is an explicit product/legal decision, updated privacy notice, user consent, and a data-minimization plan.

## Why DeepSeek is optional

- DeepSeek API is OpenAI-compatible and currently documents `deepseek-v4-flash` as an available model.
- DeepSeek Terms of Use allow applying inputs and outputs to broad legal use cases, including derivative product development.
- DeepSeek Terms also state that medical outputs are not professional advice and should not be used as the basis for important medical decisions without human review.
- DeepSeek Privacy Policy says the service is not designed or intended to process sensitive personal data, including health data.
- DeepSeek Privacy Policy says personal data may be directly collected, processed, and stored in the People's Republic of China.

## Environment flags

```bash
SLEEP_AGENT_PROVIDER=local
DEEPSEEK_API_KEY=
DEEPSEEK_MODEL=deepseek-v4-flash
DEEPSEEK_ALLOW_STRUCTURED_SUMMARY=true
DEEPSEEK_ALLOW_SENSITIVE_DATA=false
```

To test DeepSeek intentionally:

```bash
SLEEP_AGENT_PROVIDER=deepseek
DEEPSEEK_API_KEY=...
DEEPSEEK_ALLOW_STRUCTURED_SUMMARY=true
```

Even then, the runtime should send only:

- structured trend summaries
- selected education templates
- screening summaries
- red-flag and HITL signals

It should not send raw Apple Health records, raw questionnaires, or free-text sleep notes.

## Local test behavior

When DeepSeek is enabled but the API call fails, the agent keeps the local safety answer and exposes the problem in `external_model_error` and the tool trace. This prevents silent fallback during debugging.

Observed failure modes:

- `DeepSeek HTTP 402: Insufficient Balance` means the key was accepted by the API, but the account has no available balance or quota.
- Python `CERTIFICATE_VERIFY_FAILED` can occur in local environments with custom certificate chains. The backend uses `certifi` for the DeepSeek HTTPS context to avoid this failure path.
