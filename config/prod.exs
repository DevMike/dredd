import Config

# Production configuration - most values come from runtime.exs

config :llm_market, LlmMarketWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Production logging
config :logger, level: :info

# Use webhook mode for Telegram in production
config :llm_market, :telegram,
  mode: :webhook
