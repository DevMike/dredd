import Config

# Test database configuration
config :llm_market, LlmMarket.Repo,
  username: "mikezarechenskiy",
  password: "",
  hostname: "localhost",
  database: "llm_market_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Minimal Phoenix endpoint for testing
config :llm_market, LlmMarketWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_should_be_at_least_64_bytes_long_for_testing",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable Telegram in tests
config :llm_market, :telegram,
  mode: :disabled
