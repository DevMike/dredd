# LLM Market Bot - Product Requirements Document

## Overview

Build an "LLM Market Bot" where a Telegram bot orchestrates multiple LLM calls (OpenAI, Anthropic, Gemini), runs a multi-round "market" (models submit answers + confidence, then revise after seeing others), and posts the final consensus back to Telegram with buttons to inspect conflicts/raw answers. A "Dredd" (arbiter) model synthesizes the final answer from all provider responses.

**Goal**: Ship a working MVP quickly, but keep the architecture modular so a web UI (Phoenix LiveView/PWA) can be added later without rewriting core logic.

**Current Status**: MVP implemented with 3 providers (OpenAI, Anthropic, Gemini), multi-round consensus, and Telegram bot interface.

---

## Tech Stack

| Component | Choice | Notes |
|-----------|--------|-------|
| Language | Elixir + OTP | Supervision tree for fault tolerance |
| Web Framework | Phoenix (minimal) | Webhook endpoint |
| Telegram Library | Telegex | Modern, well-maintained (Nadia is older alternative) |
| HTTP Client | Finch | Performant, OTP-friendly |
| JSON | Jason | Standard for Elixir |
| Database | PostgreSQL + Ecto | Production-ready from start |
| Background Jobs | Oban (optional) | Can start without; inline with timeouts for MVP |
| Config | Runtime env vars | No secrets in repo |
| Telemetry | Telemetry + TelemetryMetrics | Standard observability |

---

## 1. Bot UX

### Commands

| Command | Description |
|---------|-------------|
| `/ask <question>` | Start a new run |
| `/last` | Show last run result |
| `/run <run_id>` | Show a specific run |
| `/raw <run_id>` | Show all provider raw answers |
| `/conflicts <run_id>` | Show conflict list with details |
| `/dredd <provider:model>` | Set default dredd (arbiter) for this chat |
| `/providers` | List enabled providers and their models |
| `/config` | Show current chat settings (dredd, max rounds, timeout) |
| `/cancel` | Cancel currently running request |
| `/status` | Show if a run is in progress |
| `/help` | Show command reference |

### Inline Buttons (on final answer)

```
[Conflicts] [Raw] [Re-run] [Cost/Latency]
```

### Access Control

- **Whitelist-only**: Only allowed `chat_id`s can use the bot
- Unauthorized users receive: "Not authorized. Contact the bot administrator."
- Whitelist configured via `WHITELIST_CHAT_IDS` env var (comma-separated)

### Input Validation

- Maximum question length: 4000 characters
- Reject empty questions
- Strip leading/trailing whitespace
- No special character restrictions (allow unicode, code blocks, etc.)

---

## 2. Orchestrator (Core)

### Fan-out Strategy

- Parallel calls to all enabled providers using `Task.Supervisor` + `Task.async_stream`
- Bounded concurrency (default: 4 simultaneous provider calls)

### Resilience Patterns

| Pattern | Configuration | Behavior |
|---------|---------------|----------|
| **Timeout** | 25s per provider | Cancel and mark as `timeout` |
| **Retries** | 2 retries | Exponential backoff on 429/5xx |
| **Rate Limiting** | Token bucket per provider | Configurable tokens/interval |
| **Circuit Breaker** | Open after 3 consecutive failures | Half-open after 30s cooldown |

### Partial Results

- Continue with available results if some providers fail/timeout
- Minimum 1 successful provider response required to proceed
- If ALL providers fail: return error response with `all_providers_failed: true`

### Tracking

- Latency (always captured)
- Token usage (if returned by provider)
- Cost (calculated or returned, see Cost Estimation section)

---

## 3. "Market" Loop

### Round 1: Initial Responses

Each provider produces structured output:

```json
{
  "answer": "string",
  "confidence": 0.85,
  "key_claims": ["claim1", "claim2"],
  "assumptions": ["assumption1"],
  "citations": [{"title": "Source", "url": "https://..."}]
}
```

### Round 2: Revision After Exposure

Each provider receives a compact summary of other providers' answers and is asked to revise.

**Summary Format** (sent to each provider):

```
## Question
{original_question}

## Your Previous Response
Answer: {their_answer}
Confidence: {their_confidence}
Key Claims: {their_claims}

## Other Providers' Responses

### OpenAI (gpt-4o) - Confidence: 0.85
Answer: {their_full_answer_truncated_to_1500_chars}

Key Claims:
- Claim A
- Claim B

### Anthropic (claude-sonnet) - Confidence: 0.78
Answer: {their_full_answer_truncated_to_1500_chars}

Key Claims:
- Claim C
- Claim D

## Detected Disagreements
- Topic X: OpenAI claims "A is true", Anthropic claims "A is false"
- Topic Y: Gemini mentions additional consideration not raised by others

## Task
Review the other responses and disagreements. Revise your answer and confidence if warranted.
Respond in the same JSON format.
```

**Note**: Full answers are included (truncated to 1500 chars) so models can see specific differences, not just key claims.

### Stopping Conditions

Stop the loop when ANY of these conditions are met:

1. **Max rounds reached**: `max_rounds` (default: 2)
2. **Convergence achieved**:
   - Confidence delta ≤ `convergence_confidence_threshold` (default: 0.1)
   - AND claim overlap ≥ `convergence_claim_overlap` (default: 0.7, Jaccard similarity)

### Convergence Calculation

```elixir
# Confidence delta: max difference between any two providers
confidence_delta = Enum.max(confidences) - Enum.min(confidences)

# Claim overlap: average pairwise Jaccard similarity of key_claims
jaccard(set_a, set_b) = |intersection| / |union|
claim_overlap = average(jaccard(p1.claims, p2.claims) for all pairs)
```

### Dredd Step

After rounds complete, the designated dredd (arbiter) model synthesizes the final answer.

**Dredd Selection Priority**:
1. Chat-specific dredd (set via `/dredd`)
2. Default dredd from config (`DEFAULT_DREDD` env var)
3. Fallback: `openai:gpt-4o`

**If Dredd Fails**:
1. Retry once with same dredd
2. Try secondary fallback dredd (`FALLBACK_DREDD` env var)
3. If all fail: return best single response (highest confidence) with `dredd_failed: true`

---

## 4. Prompt Templates

### Round 1 Prompt

```
You are participating in a multi-model consensus process. Answer the following question thoroughly and honestly.

IMPORTANT: Your answer MUST be in the SAME LANGUAGE as the question below.

Question: {question}

Respond with ONLY valid JSON matching this exact schema (no markdown, no explanation):
{
  "answer": "Your complete answer as a string",
  "confidence": <number 0.0 to 1.0 representing your confidence>,
  "key_claims": ["list", "of", "main", "factual", "claims"],
  "assumptions": ["list", "of", "assumptions", "you", "made"],
  "citations": [{"title": "Source name or null", "url": "URL or null"}]
}

Guidelines:
- confidence: 0.0 = pure guess, 0.5 = uncertain, 0.8 = confident, 0.95+ = very certain
- key_claims: Extract 3-7 main factual assertions from your answer
- assumptions: Note any assumptions that if wrong would change your answer
- citations: Include if you reference specific sources; can be empty array
```

### Round 2 Prompt

```
You previously answered a question in a multi-model consensus process. You will now see how other models answered.

IMPORTANT: Your answer MUST be in the SAME LANGUAGE as the question below.

{summary_format_from_above}

Respond with ONLY valid JSON matching the same schema. You may:
- Keep your answer if you believe it's correct
- Revise your answer based on valid points from others
- Adjust your confidence based on agreement/disagreement

Do NOT simply agree with the majority. Maintain your position if you believe you're correct.
```

### Dredd Prompt

```
You are the Dredd (arbiter) in a multi-model consensus process. Multiple AI models have answered a question across {num_rounds} rounds. Your task is to synthesize a final answer.

IMPORTANT: Your final_answer MUST be in the SAME LANGUAGE as the question below.

Question: {question}

Model Responses (final round):
{formatted_responses}

Analyze the responses and produce ONLY valid JSON matching this exact schema:
{
  "final_answer": "The synthesized, accurate answer",
  "agreements": ["Points all or most models agree on"],
  "conflicts": [
    {
      "topic": "Brief topic description",
      "claims": [
        {"provider": "openai", "claim": "Their position"},
        {"provider": "anthropic", "claim": "Their position"}
      ],
      "resolution": "Your resolution of this conflict with reasoning",
      "status": "RESOLVED or UNRESOLVED",
      "confidence": <0.0-1.0 confidence in your resolution>
    }
  ],
  "fact_table": [
    {"claim": "A factual claim", "support": ["openai", "gemini"], "confidence": 0.9}
  ],
  "next_questions": ["Follow-up questions that could clarify uncertainties"],
  "overall_confidence": <0.0-1.0>,
  "dredd_failed": false
}

Guidelines:
- Prefer claims with more model support and higher confidence
- Mark conflicts UNRESOLVED if you cannot determine which is correct
- overall_confidence reflects confidence in final_answer, not just agreement level
```

### Schema Parsing Fallback

If a provider response doesn't parse as valid JSON:

1. Attempt to extract JSON from markdown code blocks
2. Attempt to fix common issues (trailing commas, unquoted keys)
3. If still failing: create minimal valid response with `parse_error: true`

```elixir
%{
  answer: raw_text_response,
  confidence: nil,
  key_claims: nil,
  assumptions: nil,
  citations: nil,
  parse_error: true,
  raw_response: truncated_raw_response
}
```

---

## 5. Canonical Schemas

### A) Normalized Provider Answer

```json
{
  "run_id": "uuid",
  "round": 1,
  "provider": "openai|gemini|perplexity|anthropic",
  "model": "string",
  "status": "ok|error|timeout|parse_error",
  "answer": "string",
  "confidence": 0.85,
  "key_claims": ["string"],
  "assumptions": ["string"],
  "citations": [{"title": "string|null", "url": "string|null"}],
  "usage": {
    "input_tokens": 150,
    "output_tokens": 500,
    "total_tokens": 650,
    "cost_usd": 0.0023
  },
  "latency_ms": 2340,
  "error": {
    "type": "rate_limit|server_error|timeout|parse_error|safety_block",
    "message": "string",
    "http_status": 429
  },
  "parse_error": false,
  "raw_response": "string|null"
}
```

### B) Dredd Input Bundle

```json
{
  "question": "string",
  "answers": ["Array of NormalizedAnswer"],
  "rounds_completed": 2,
  "convergence_achieved": false,
  "metadata": {
    "run_id": "uuid",
    "timestamp": "ISO8601",
    "settings": {
      "max_rounds": 2,
      "convergence_threshold": 0.1
    }
  }
}
```

### C) Dredd Output Schema

```json
{
  "final_answer": "string",
  "agreements": ["string"],
  "conflicts": [
    {
      "topic": "string",
      "claims": [{"provider": "string", "claim": "string"}],
      "resolution": "string",
      "status": "RESOLVED|UNRESOLVED",
      "confidence": 0.85
    }
  ],
  "fact_table": [
    {"claim": "string", "support": ["provider"], "confidence": 0.9}
  ],
  "next_questions": ["string"],
  "overall_confidence": 0.82,
  "dredd_failed": false
}
```

### D) Run Summary (for Telegram display)

```json
{
  "run_id": "uuid",
  "status": "completed|failed|cancelled|in_progress",
  "question": "string (truncated to 200 chars)",
  "final_answer": "string",
  "overall_confidence": 0.85,
  "providers_succeeded": 3,
  "providers_failed": 1,
  "rounds_completed": 2,
  "total_latency_ms": 4500,
  "total_cost_usd": 0.015,
  "conflict_count": 2,
  "created_at": "ISO8601"
}
```

---

## 6. Provider Integration

### Adapter Interface

All providers implement the same behaviour:

```elixir
@callback call(prompt :: String.t(), opts :: keyword()) ::
  {:ok, raw_response :: map()} | {:error, error :: map()}

@callback normalize(raw_response :: map()) :: NormalizedAnswer.t()

@callback estimate_cost(usage :: map(), model :: String.t()) :: float() | nil
```

### Provider-Specific Notes

| Provider | API | Notes |
|----------|-----|-------|
| **OpenAI** | Chat Completions | Use `response_format: {type: "json_object"}` for JSON mode |
| **Anthropic** | Messages API | Map `stop_reason`, handle `content` blocks |
| **Gemini** | generateContent | Handle `safety_ratings`, empty `candidates` as errors |
| ~~Perplexity~~ | ~~OpenAI-compatible~~ | *Not implemented in MVP* |

### Model Configuration

```elixir
config :llm_market, :providers,
  openai: %{
    enabled: true,
    models: ["gpt-4o", "gpt-4o-mini"],
    default_model: "gpt-4o",
    api_key_env: "OPENAI_API_KEY",
    rate_limit: {10, :per_second},
    timeout_ms: 25_000
  },
  anthropic: %{
    enabled: true,
    models: ["claude-sonnet-4-20250514", "claude-haiku-4-20250514"],
    default_model: "claude-sonnet-4-20250514",
    api_key_env: "ANTHROPIC_API_KEY",
    rate_limit: {5, :per_second},
    timeout_ms: 30_000
  },
  gemini: %{
    enabled: true,
    models: ["gemini-2.5-flash", "gemini-2.5-pro"],
    default_model: "gemini-2.5-flash",
    api_key_env: "GEMINI_API_KEY",
    rate_limit: {10, :per_second},
    timeout_ms: 25_000
  }
  # Perplexity not implemented in MVP
```

---

## 7. Cost Estimation

### Strategy

1. **Use provider-reported cost** if available in response
2. **Calculate from tokens** if usage data present but no cost
3. **Store null** if no usage data available

### Cost Table (USD per 1K tokens, approximate)

```elixir
@costs %{
  # OpenAI
  "gpt-4o" => %{input: 0.0025, output: 0.010},
  "gpt-4o-mini" => %{input: 0.00015, output: 0.0006},

  # Anthropic
  "claude-sonnet-4-20250514" => %{input: 0.003, output: 0.015},
  "claude-haiku-4-20250514" => %{input: 0.0008, output: 0.004},

  # Gemini
  "gemini-2.0-flash" => %{input: 0.0001, output: 0.0004},
  "gemini-2.5-flash" => %{input: 0.00015, output: 0.0006},
  "gemini-2.5-pro" => %{input: 0.00125, output: 0.005}
}
```

**Note**: Cost calculator supports prefix matching, so `gpt-4o-2024-08-06` matches `gpt-4o` pricing.

### Cost Calculation

```elixir
def calculate_cost(model, input_tokens, output_tokens) do
  case Map.get(@costs, model) do
    nil -> nil
    rates ->
      (input_tokens * rates.input / 1000) +
      (output_tokens * rates.output / 1000)
  end
end
```

---

## 8. Persistence & Data Model

### Database Schema

```
threads
  - id: uuid (PK)
  - telegram_chat_id: bigint (unique, indexed)
  - default_dredd_provider: string
  - default_dredd_model: string
  - settings: jsonb
  - created_at: timestamp
  - updated_at: timestamp

runs
  - id: uuid (PK)
  - thread_id: uuid (FK)
  - question: text
  - status: enum (pending, in_progress, completed, failed, cancelled)
  - rounds_completed: integer
  - convergence_achieved: boolean
  - total_latency_ms: integer
  - total_cost_usd: decimal
  - created_at: timestamp
  - updated_at: timestamp

provider_answers
  - id: uuid (PK)
  - run_id: uuid (FK, indexed)
  - round: integer
  - provider: string
  - model: string
  - status: enum (ok, error, timeout, parse_error)
  - answer: text
  - confidence: decimal
  - key_claims: jsonb
  - assumptions: jsonb
  - citations: jsonb
  - usage: jsonb
  - latency_ms: integer
  - error: jsonb
  - raw_response: text (nullable, only in debug mode)
  - created_at: timestamp

dredd_outputs
  - id: uuid (PK)
  - run_id: uuid (FK, unique, indexed)
  - dredd_provider: string
  - dredd_model: string
  - final_answer: text
  - agreements: jsonb
  - conflicts: jsonb
  - fact_table: jsonb
  - next_questions: jsonb
  - overall_confidence: decimal
  - dredd_failed: boolean
  - latency_ms: integer
  - cost_usd: decimal
  - created_at: timestamp

metrics (optional, for analytics)
  - id: uuid (PK)
  - run_id: uuid (FK, indexed)
  - event_type: string
  - provider: string
  - data: jsonb
  - timestamp: timestamp
```

### Data Retention

- **Default retention**: 30 days (`RUN_RETENTION_DAYS` env var)
- **Cleanup job**: Daily Oban job or manual mix task
- **Raw responses**: Only stored if `DEBUG_MODE=true`, auto-deleted after 7 days

### Run Replay

```bash
# CLI task to re-render a run without re-calling providers
mix llm_market.replay <run_id>

# Or via HTTP endpoint
GET /api/runs/:run_id/replay
```

---

## 9. Observability

### Logging Levels

| Level | Content |
|-------|---------|
| **info** (default) | Metadata only: run_id, provider, status, latency_ms |
| **debug** | + Truncated prompts (first 500 chars), response previews |

**NEVER log**: API keys, full responses (unless debug), user PII

### Telemetry Events

```elixir
# Provider call
[:llm_market, :provider, :call, :start]
[:llm_market, :provider, :call, :stop]
[:llm_market, :provider, :call, :exception]

# Measurements: latency_ms, tokens, cost_usd
# Metadata: provider, model, status, run_id

# Run lifecycle
[:llm_market, :run, :start]
[:llm_market, :run, :round_complete]
[:llm_market, :run, :complete]
[:llm_market, :run, :failed]

# Circuit breaker
[:llm_market, :circuit_breaker, :open]
[:llm_market, :circuit_breaker, :half_open]
[:llm_market, :circuit_breaker, :close]
```

### Health Endpoint

```
GET /health

Response:
{
  "status": "ok|degraded|unhealthy",
  "version": "0.1.0",
  "providers": {
    "openai": {"status": "ok", "circuit": "closed"},
    "anthropic": {"status": "ok", "circuit": "closed"},
    "gemini": {"status": "degraded", "circuit": "half_open"},
    "perplexity": {"status": "unhealthy", "circuit": "open"}
  },
  "database": "ok",
  "telegram": "ok"
}
```

### Metrics Export (Optional)

Support for Prometheus via `TelemetryMetricsPrometheus`:

```
llm_market_provider_call_duration_seconds{provider, model, status}
llm_market_provider_call_tokens_total{provider, model, type}
llm_market_provider_call_cost_usd{provider, model}
llm_market_run_duration_seconds{status}
llm_market_circuit_breaker_state{provider}
```

---

## 10. Architecture (OTP)

### Supervision Tree (Current Implementation)

```
Application
├── Repo (Ecto)
├── Finch (HTTP client pool)
├── Phoenix.Endpoint
│   └── Controllers (webhook, health, run)
├── OrchestratorSupervisor
│   └── ProviderClientSupervisor
│       ├── OpenAIClient (GenServer with rate limiter + circuit breaker)
│       ├── AnthropicClient (GenServer)
│       └── GeminiClient (GenServer)
└── TelegramPoller (polling mode for updates)
```

**Note**: Oban not implemented in MVP. Cleanup jobs can be added later.

### ProviderClient Responsibilities

- Maintains circuit breaker state
- Manages rate limiting (token bucket)
- Handles retries with backoff
- Emits telemetry events

### RunCoordinator Responsibilities

- Manages round progression
- Coordinates fan-out to providers
- Handles partial results
- Persists state after each round
- Invokes judge and persists final output

### Concurrency Guidelines

- Fan-out: `Task.Supervisor` + `Task.async_stream` with `max_concurrency: 4`
- No global mutable state outside GenServers
- All provider state isolated in respective GenServer

---

## 11. Module Boundaries (Future-Proofing)

```
lib/
├── llm_market/
│   ├── core/              # Pure business logic
│   │   ├── market.ex      # Market loop orchestration
│   │   ├── dredd.ex       # Dredd (arbiter) synthesis logic
│   │   ├── convergence.ex # Convergence calculation (Jaccard, delta)
│   │   └── prompts.ex     # Prompt templates (Round 1, Round 2, Dredd)
│   │
│   ├── providers/         # Provider adapters
│   │   ├── behaviour.ex   # Provider behaviour definition
│   │   ├── base.ex        # Shared HTTP/parsing logic
│   │   ├── openai.ex
│   │   ├── anthropic.ex
│   │   ├── gemini.ex
│   │   └── cost_calculator.ex  # Model pricing with prefix matching
│   │
│   ├── orchestrator/      # OTP processes
│   │   ├── supervisor.ex
│   │   ├── provider_client.ex      # GenServer with circuit breaker
│   │   ├── provider_client_supervisor.ex
│   │   ├── rate_limiter.ex         # Token bucket implementation
│   │   └── circuit_breaker.ex      # Circuit breaker state machine
│   │
│   ├── telegram/          # Telegram-specific
│   │   ├── bot.ex         # Main entry point, update handling
│   │   ├── commands.ex    # Command handlers
│   │   ├── auth.ex        # Whitelist authorization
│   │   ├── formatter.ex   # Format responses for Telegram (plain text)
│   │   ├── keyboards.ex   # Inline button builders
│   │   └── poller.ex      # Polling-based update fetcher
│   │
│   ├── schemas/           # Ecto schemas
│   │   ├── thread.ex
│   │   ├── run.ex
│   │   ├── provider_answer.ex
│   │   └── dredd_output.ex
│   │
│   ├── repo.ex
│   └── application.ex
│
├── llm_market_web/        # Phoenix (minimal for MVP)
│   ├── endpoint.ex
│   ├── router.ex
│   └── controllers/
│       ├── webhook_controller.ex
│       ├── health_controller.ex
│       └── run_controller.ex
│
└── mix.exs
```

---

## 12. Configuration

### Environment Variables

```bash
# Required
TELEGRAM_BOT_TOKEN=         # From @BotFather
WHITELIST_CHAT_IDS=123456,789012  # Comma-separated allowed chat IDs
SECRET_KEY_BASE=            # Phoenix secret (generate with mix phx.gen.secret)
DATABASE_URL=               # PostgreSQL connection string

# Provider API Keys (at least one required)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=

# Optional
DEFAULT_DREDD=openai:gpt-4o
FALLBACK_DREDD=anthropic:claude-sonnet-4-20250514
WEBHOOK_URL=https://your-domain.com/webhook/telegram
DEBUG_MODE=false
RUN_RETENTION_DAYS=30
LOG_LEVEL=info

# Tuning (with defaults)
MAX_ROUNDS=5
PROVIDER_TIMEOUT_MS=25000
MAX_RETRIES=2
MAX_CONCURRENCY=4
CONVERGENCE_CONFIDENCE_THRESHOLD=0.1
CONVERGENCE_CLAIM_OVERLAP=0.7
MAX_QUESTION_LENGTH=4000
```

### .env.example

```bash
# LLM Market Bot Configuration
# Copy to .env and fill in values

# === Required ===
TELEGRAM_BOT_TOKEN=your_bot_token_here
WHITELIST_CHAT_IDS=your_chat_id_here
SECRET_KEY_BASE=generate_with_mix_phx_gen_secret
DATABASE_URL=postgres://user:pass@localhost/llm_market_dev

# === Provider API Keys (at least one) ===
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...

# === Optional ===
# DEFAULT_DREDD=openai:gpt-4o
# FALLBACK_DREDD=anthropic:claude-sonnet-4-20250514
# WEBHOOK_URL=https://your-ngrok-url.ngrok.io/webhook/telegram
# DEBUG_MODE=false
# LOG_LEVEL=info
```

---

## 13. Security Considerations

### Access Control

- Whitelist-only access via `WHITELIST_CHAT_IDS`
- All unauthorized requests logged with chat_id for monitoring

### Prompt Injection Mitigation

- User questions wrapped in clear delimiters
- System prompts emphasize JSON-only output
- Validation rejects responses that don't match schema
- Consider: content filtering on user input (optional)

### Secret Management

- All secrets via environment variables
- Never log API keys (enforced in logger config)
- Raw responses only stored in debug mode with auto-expiry

### Input Validation

- Question length limit (4000 chars)
- UTF-8 validation
- Reject control characters except newlines

---

## 14. Error Handling

### Error Categories

| Scenario | Handling |
|----------|----------|
| Single provider fails | Continue with others, mark as failed |
| All providers fail | Return error with `all_providers_failed: true` |
| Dredd fails | Try fallback dredd, then return best single response |
| Parse error | Store raw response, use with `parse_error: true` |
| Rate limited | Backoff and retry, open circuit if persistent |
| Telegram API error | Log and notify user if possible |
| Database error | Fail run, notify user |
| Timeout | Mark provider as timeout, continue with others |

### User-Facing Error Messages

Keep errors helpful but not leaking internals:

```
# All providers failed
"Unable to get responses from any provider. Please try again later."

# Dredd failed
"Partial results available, but synthesis failed. Showing best individual response."

# Rate limited
"Too many requests. Please wait a moment and try again."

# Cancelled
"Request cancelled."
```

---

## 15. Testing Strategy

### Required Tests

1. **Schema validation**
   - Valid/invalid provider answer parsing
   - Judge output schema validation

2. **Provider adapters**
   - HTTP mocking with Mox/Bypass
   - Error response handling
   - Token/cost extraction

3. **Resilience patterns**
   - Rate limiter token bucket behavior
   - Circuit breaker state transitions
   - Retry with backoff

4. **RunCoordinator**
   - Round progression with stubbed providers
   - Convergence detection
   - Partial result handling

5. **Telegram integration**
   - Command parsing
   - Authorization check
   - Message formatting

### Test Setup

```elixir
# test/support/mocks.ex
Mox.defmock(LlmMarket.Providers.MockProvider, for: LlmMarket.Providers.Behaviour)

# test/support/fixtures.ex
# Reusable test data for provider responses, runs, etc.
```

---

## 16. Deliverables

1. **Full repo scaffold** with file tree
2. **All source files**: mix.exs, config/*, lib/*, priv/repo/migrations/*
3. **README** with:
   - How to create Telegram bot token
   - How to set webhook (ngrok for local) OR polling mode
   - Environment variable reference
   - Command demo / screenshots
4. **Tests** as specified above
5. **Mix tasks**:
   - `mix llm_market.setup` - DB create + migrate
   - `mix llm_market.replay <run_id>` - Re-render a run

---

## 17. Defaults Summary

| Setting | Default |
|---------|---------|
| max_rounds | 5 |
| provider_timeout_ms | 25000 |
| max_retries | 2 |
| max_concurrency | 4 |
| convergence_confidence_threshold | 0.1 |
| convergence_claim_overlap | 0.7 |
| run_retention_days | 30 |
| max_question_length | 4000 |
| database | PostgreSQL |
| telegram_updates | Polling (webhook also supported) |
| default_dredd | openai:gpt-4o |

---

## 18. MVP Implementation Status

### ✅ Implemented
- [x] 3 providers: OpenAI, Anthropic, Gemini
- [x] Multi-round consensus (up to 5 rounds)
- [x] Convergence detection (Jaccard similarity, confidence delta)
- [x] Dredd (arbiter) synthesis with fallback
- [x] Telegram bot with all commands
- [x] Whitelist authorization
- [x] Circuit breaker and rate limiting
- [x] Cost calculation with prefix matching
- [x] PostgreSQL persistence
- [x] Health endpoint
- [x] Polling mode for Telegram

### ⏳ Not Yet Implemented
- [ ] Perplexity provider
- [ ] Oban for background jobs
- [ ] `mix llm_market.replay` command
- [ ] Metrics table for analytics
- [ ] Prometheus metrics export
- [ ] Run cleanup job (retention)

---

## 19. Open Questions / Future Considerations

- [ ] Web UI (Phoenix LiveView) - Phase 2
- [ ] Multi-user support with per-user quotas
- [ ] Custom model selection per run
- [ ] Streaming responses to Telegram
- [ ] Image/multimodal support
- [ ] Conversation context (follow-up questions)
- [ ] Export runs to markdown/PDF
- [ ] Admin dashboard for monitoring
