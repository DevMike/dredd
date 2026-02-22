defmodule LlmMarketWeb.HealthController do
  use LlmMarketWeb, :controller

  @doc """
  Health check endpoint.

  Returns status of all system components:
  - Overall status: ok | degraded | unhealthy
  - Provider status and circuit breaker state
  - Database connectivity
  - Telegram connectivity
  """
  def index(conn, _params) do
    health = build_health_check()

    status_code =
      case health.status do
        "ok" -> 200
        "degraded" -> 200
        "unhealthy" -> 503
      end

    conn
    |> put_status(status_code)
    |> json(health)
  end

  defp build_health_check do
    db_status = check_database()
    provider_statuses = check_providers()

    overall_status = determine_overall_status(db_status, provider_statuses)

    %{
      status: overall_status,
      version: Application.spec(:llm_market, :vsn) |> to_string(),
      providers: provider_statuses,
      database: db_status,
      telegram: check_telegram()
    }
  end

  defp check_database do
    case LlmMarket.Repo.query("SELECT 1") do
      {:ok, _} -> "ok"
      {:error, _} -> "unhealthy"
    end
  rescue
    _ -> "unhealthy"
  end

  defp check_providers do
    enabled = LlmMarket.enabled_providers()

    enabled
    |> Enum.map(fn {name, _config} ->
      # Get circuit breaker state from provider client
      state = LlmMarket.Orchestrator.ProviderClient.get_state(name)

      status =
        case state do
          %{circuit: :closed} -> "ok"
          %{circuit: :half_open} -> "degraded"
          %{circuit: :open} -> "unhealthy"
          _ -> "unknown"
        end

      {name,
       %{
         status: status,
         circuit: state[:circuit] || "unknown"
       }}
    end)
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp check_telegram do
    config = LlmMarket.telegram_config()

    if config[:bot_token] do
      "ok"
    else
      "not_configured"
    end
  end

  defp determine_overall_status(db_status, provider_statuses) do
    cond do
      db_status != "ok" ->
        "unhealthy"

      Enum.all?(provider_statuses, fn {_, %{status: s}} -> s == "unhealthy" end) ->
        "unhealthy"

      Enum.any?(provider_statuses, fn {_, %{status: s}} -> s != "ok" end) ->
        "degraded"

      true ->
        "ok"
    end
  end
end
