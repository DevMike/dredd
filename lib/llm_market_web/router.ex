defmodule LlmMarketWeb.Router do
  use LlmMarketWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check endpoint (no auth required)
  scope "/", LlmMarketWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Telegram webhook endpoint
  scope "/webhook", LlmMarketWeb do
    pipe_through :api

    post "/telegram", WebhookController, :telegram
  end

  # API endpoints (for future web UI)
  scope "/api", LlmMarketWeb do
    pipe_through :api

    get "/runs/:id", RunController, :show
    get "/runs/:id/replay", RunController, :replay
  end
end
