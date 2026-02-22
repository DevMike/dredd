import Config

config :llm_market,
  ecto_repos: [LlmMarket.Repo],
  generators: [timestamp_type: :utc_datetime]

# Phoenix endpoint configuration
config :llm_market, LlmMarketWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: LlmMarketWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LlmMarket.PubSub,
  live_view: [signing_salt: "llm_market_salt"]

# JSON library
config :phoenix, :json_library, Jason

# Logger configuration - never log secrets
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :run_id, :provider]

# Provider configuration defaults
config :llm_market, :providers,
  openai: %{
    enabled: true,
    models: ["gpt-4o", "gpt-4o-mini"],
    default_model: "gpt-4o",
    base_url: "https://api.openai.com/v1",
    rate_limit: {10, :per_second},
    timeout_ms: 25_000
  },
  anthropic: %{
    enabled: true,
    models: ["claude-sonnet-4-20250514", "claude-haiku-4-20250514"],
    default_model: "claude-sonnet-4-20250514",
    base_url: "https://api.anthropic.com",
    rate_limit: {5, :per_second},
    timeout_ms: 30_000
  },
  gemini: %{
    enabled: true,
    models: ["gemini-2.5-flash", "gemini-2.5-pro"],
    default_model: "gemini-2.5-flash",
    base_url: "https://generativelanguage.googleapis.com/v1beta",
    rate_limit: {10, :per_second},
    timeout_ms: 25_000
  }

# Market configuration defaults
config :llm_market, :market,
  max_rounds: 5,
  max_concurrency: 4,
  convergence_confidence_threshold: 0.1,
  convergence_claim_overlap: 0.7

# Bot configuration defaults
config :llm_market, :bot,
  max_question_length: 4000,
  run_retention_days: 30

# Import environment specific config
import_config "#{config_env()}.exs"
