defmodule LlmMarket.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Telemetry supervisor (must start first)
      LlmMarket.Telemetry,

      # Database
      LlmMarket.Repo,

      # PubSub for Phoenix
      {Phoenix.PubSub, name: LlmMarket.PubSub},

      # HTTP client pool
      {Finch, name: LlmMarket.Finch},

      # Registry for provider clients
      {Registry, keys: :unique, name: LlmMarket.Orchestrator.Registry},

      # Phoenix endpoint
      LlmMarketWeb.Endpoint,

      # Orchestrator supervisor (provider clients, run coordinators)
      LlmMarket.Orchestrator.Supervisor,

      # Telegram pending prompts storage
      LlmMarket.Telegram.PendingPrompts,

      # Telegram bot (conditionally started based on config)
      telegram_child_spec()
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: LlmMarket.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LlmMarketWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp telegram_child_spec do
    config = Application.get_env(:llm_market, :telegram, %{})

    case config[:mode] do
      :polling ->
        LlmMarket.Telegram.Poller

      :webhook ->
        # Webhook is handled by Phoenix endpoint, no separate process needed
        nil

      :disabled ->
        nil

      _ ->
        nil
    end
  end
end
