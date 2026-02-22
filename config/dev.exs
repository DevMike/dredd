import Config

# Database configuration for development
config :llm_market, LlmMarket.Repo,
  username: "mikezarechenskiy",
  password: "",
  hostname: "localhost",
  database: "llm_market_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Phoenix endpoint for development
config :llm_market, LlmMarketWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_should_be_at_least_64_bytes_long_for_security",
  watchers: []

# Development logging
config :logger, :console, format: "[$level] $message\n"

# Development mode settings
config :phoenix, :plug_init_mode, :runtime

# Use polling mode for Telegram in development (easier than webhook)
config :llm_market, :telegram,
  mode: :polling,
  polling_interval: 1000
