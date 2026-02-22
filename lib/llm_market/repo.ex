defmodule LlmMarket.Repo do
  use Ecto.Repo,
    otp_app: :llm_market,
    adapter: Ecto.Adapters.Postgres
end
