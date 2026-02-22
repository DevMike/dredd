defmodule LlmMarket.Orchestrator.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation with three states:
  - :closed - Normal operation, requests flow through
  - :open - Too many failures, requests blocked
  - :half_open - Testing if service recovered

  State transitions:
  - closed -> open: After N consecutive failures
  - open -> half_open: After recovery timeout
  - half_open -> closed: On successful request
  - half_open -> open: On failed request
  """

  alias LlmMarket.Telemetry

  defstruct [
    :provider,
    :state,
    :failure_count,
    :failure_threshold,
    :recovery_timeout,
    :last_failure_time
  ]

  @doc """
  Create a new circuit breaker.
  """
  def new(opts \\ []) do
    %__MODULE__{
      provider: opts[:provider],
      state: :closed,
      failure_count: 0,
      failure_threshold: opts[:failure_threshold] || 3,
      recovery_timeout: opts[:recovery_timeout] || 30_000,
      last_failure_time: nil
    }
  end

  @doc """
  Check if request is allowed. Returns {:ok, updated_cb} or {:error, :circuit_open}.
  """
  def allow?(%__MODULE__{state: :closed} = cb), do: {:ok, cb}

  def allow?(%__MODULE__{state: :open} = cb) do
    now = System.monotonic_time(:millisecond)

    if now - cb.last_failure_time >= cb.recovery_timeout do
      # Transition to half-open
      {:ok, %{cb | state: :half_open}}
    else
      {:error, :circuit_open}
    end
  end

  def allow?(%__MODULE__{state: :half_open} = cb), do: {:ok, cb}

  @doc """
  Record a successful request.
  """
  def record_success(%__MODULE__{state: :half_open, provider: provider} = cb)
      when not is_nil(provider) do
    Telemetry.circuit_breaker_close(provider)
    %{cb | state: :closed, failure_count: 0}
  end

  def record_success(%__MODULE__{state: :half_open} = cb) do
    %{cb | state: :closed, failure_count: 0}
  end

  def record_success(cb), do: %{cb | failure_count: 0}

  @doc """
  Record a failed request.
  """
  def record_failure(%__MODULE__{state: :half_open, provider: provider} = cb)
      when not is_nil(provider) do
    # Back to open
    now = System.monotonic_time(:millisecond)
    Telemetry.circuit_breaker_open(provider)
    %{cb | state: :open, last_failure_time: now}
  end

  def record_failure(%__MODULE__{state: :half_open} = cb) do
    now = System.monotonic_time(:millisecond)
    %{cb | state: :open, last_failure_time: now}
  end

  def record_failure(%__MODULE__{state: :closed} = cb) do
    new_count = cb.failure_count + 1

    if new_count >= cb.failure_threshold do
      # Open the circuit
      now = System.monotonic_time(:millisecond)
      %{cb | state: :open, failure_count: new_count, last_failure_time: now}
    else
      %{cb | failure_count: new_count}
    end
  end

  def record_failure(%__MODULE__{state: :open} = cb) do
    # Already open, just update timestamp
    now = System.monotonic_time(:millisecond)
    %{cb | last_failure_time: now}
  end
end
