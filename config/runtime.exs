import Config

# Runtime configuration from environment variables

# Helper to parse integer env vars with defaults
get_int = fn key, default ->
  case System.get_env(key) do
    nil -> default
    val -> String.to_integer(val)
  end
end

# Helper to parse float env vars with defaults
get_float = fn key, default ->
  case System.get_env(key) do
    nil -> default
    val -> String.to_float(val)
  end
end

# Helper to parse boolean env vars
get_bool = fn key, default ->
  case System.get_env(key) do
    nil -> default
    "true" -> true
    "1" -> true
    _ -> false
  end
end

# Helper to parse comma-separated list
get_list = fn key ->
  case System.get_env(key) do
    nil -> []
    val -> String.split(val, ",") |> Enum.map(&String.trim/1)
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :llm_market, LlmMarket.Repo,
    url: database_url,
    pool_size: get_int.("POOL_SIZE", 10)

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = get_int.("PORT", 4000)

  config :llm_market, LlmMarketWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end

# Telegram configuration (all environments)
telegram_token = System.get_env("TELEGRAM_BOT_TOKEN")

config :llm_market, :telegram,
  bot_token: telegram_token,
  webhook_url: System.get_env("WEBHOOK_URL"),
  whitelist_chat_ids:
    get_list.("WHITELIST_CHAT_IDS")
    |> Enum.map(&String.to_integer/1)
    |> MapSet.new()

# Telegex configuration
if telegram_token do
  config :telegex,
    token: telegram_token,
    caller_adapter: {Finch, receive_timeout: 35_000}
end

# Provider API keys
config :llm_market, :api_keys,
  openai: System.get_env("OPENAI_API_KEY"),
  anthropic: System.get_env("ANTHROPIC_API_KEY"),
  gemini: System.get_env("GEMINI_API_KEY")

# Dredd (arbiter) configuration
default_dredd =
  case System.get_env("DEFAULT_DREDD") do
    nil ->
      {:openai, "gpt-4o"}

    val ->
      [provider, model] = String.split(val, ":")
      {String.to_atom(provider), model}
  end

fallback_dredd =
  case System.get_env("FALLBACK_DREDD") do
    nil ->
      {:openai, "gpt-4o"}

    val ->
      [provider, model] = String.split(val, ":")
      {String.to_atom(provider), model}
  end

config :llm_market, :dredd,
  default: default_dredd,
  fallback: fallback_dredd

# Market tuning from environment
config :llm_market, :market,
  max_rounds: get_int.("MAX_ROUNDS", 2),
  provider_timeout_ms: get_int.("PROVIDER_TIMEOUT_MS", 25_000),
  max_retries: get_int.("MAX_RETRIES", 2),
  max_concurrency: get_int.("MAX_CONCURRENCY", 4),
  convergence_confidence_threshold: get_float.("CONVERGENCE_CONFIDENCE_THRESHOLD", 0.1),
  convergence_claim_overlap: get_float.("CONVERGENCE_CLAIM_OVERLAP", 0.7)

# Bot tuning from environment
config :llm_market, :bot,
  max_question_length: get_int.("MAX_QUESTION_LENGTH", 4000),
  run_retention_days: get_int.("RUN_RETENTION_DAYS", 30),
  debug_mode: get_bool.("DEBUG_MODE", false)

# Log level from environment
if log_level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_atom(log_level)
end
