defmodule LlmMarket.Telemetry do
  @moduledoc """
  Telemetry events and metrics for the LLM Market application.

  ## Events

  ### Provider calls
  - `[:llm_market, :provider, :call, :start]` - Provider call started
  - `[:llm_market, :provider, :call, :stop]` - Provider call completed
  - `[:llm_market, :provider, :call, :exception]` - Provider call failed

  ### Run lifecycle
  - `[:llm_market, :run, :start]` - Run started
  - `[:llm_market, :run, :round_complete]` - Round completed
  - `[:llm_market, :run, :complete]` - Run completed successfully
  - `[:llm_market, :run, :failed]` - Run failed

  ### Circuit breaker
  - `[:llm_market, :circuit_breaker, :open]` - Circuit opened
  - `[:llm_market, :circuit_breaker, :half_open]` - Circuit half-open
  - `[:llm_market, :circuit_breaker, :close]` - Circuit closed
  """

  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_stats, []}
    ]
  end

  @doc """
  Emit periodic stats (called by telemetry_poller).
  """
  def emit_stats do
    # Placeholder for periodic metrics
    :ok
  end

  @doc """
  Execute a function with telemetry span.
  """
  def span(event_name, metadata, fun) when is_list(event_name) and is_function(fun, 0) do
    :telemetry.span(event_name, metadata, fn ->
      result = fun.()
      {result, %{}}
    end)
  end

  @doc """
  Emit a telemetry event.
  """
  def emit(event_name, measurements, metadata \\ %{}) do
    :telemetry.execute(event_name, measurements, metadata)
  end

  # Provider call events
  def provider_call_start(provider, model, run_id) do
    emit(
      [:llm_market, :provider, :call, :start],
      %{system_time: System.system_time()},
      %{provider: provider, model: model, run_id: run_id}
    )
  end

  def provider_call_stop(provider, model, run_id, duration_ms, status, tokens \\ nil, cost \\ nil) do
    measurements = %{
      duration_ms: duration_ms,
      tokens: tokens || 0,
      cost_usd: cost || 0.0
    }

    emit(
      [:llm_market, :provider, :call, :stop],
      measurements,
      %{provider: provider, model: model, run_id: run_id, status: status}
    )
  end

  def provider_call_exception(provider, model, run_id, kind, reason) do
    emit(
      [:llm_market, :provider, :call, :exception],
      %{system_time: System.system_time()},
      %{provider: provider, model: model, run_id: run_id, kind: kind, reason: reason}
    )
  end

  # Run lifecycle events
  def run_start(run_id, question) do
    emit(
      [:llm_market, :run, :start],
      %{system_time: System.system_time()},
      %{run_id: run_id, question_length: String.length(question)}
    )
  end

  def run_round_complete(run_id, round, provider_count, duration_ms) do
    emit(
      [:llm_market, :run, :round_complete],
      %{duration_ms: duration_ms, provider_count: provider_count},
      %{run_id: run_id, round: round}
    )
  end

  def run_complete(run_id, total_duration_ms, total_cost) do
    emit(
      [:llm_market, :run, :complete],
      %{duration_ms: total_duration_ms, cost_usd: total_cost || 0.0},
      %{run_id: run_id}
    )
  end

  def run_failed(run_id, reason) do
    emit(
      [:llm_market, :run, :failed],
      %{system_time: System.system_time()},
      %{run_id: run_id, reason: reason}
    )
  end

  # Circuit breaker events
  def circuit_breaker_open(provider) do
    emit(
      [:llm_market, :circuit_breaker, :open],
      %{system_time: System.system_time()},
      %{provider: provider}
    )
  end

  def circuit_breaker_half_open(provider) do
    emit(
      [:llm_market, :circuit_breaker, :half_open],
      %{system_time: System.system_time()},
      %{provider: provider}
    )
  end

  def circuit_breaker_close(provider) do
    emit(
      [:llm_market, :circuit_breaker, :close],
      %{system_time: System.system_time()},
      %{provider: provider}
    )
  end
end
