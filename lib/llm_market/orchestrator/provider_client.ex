defmodule LlmMarket.Orchestrator.ProviderClient do
  @moduledoc """
  GenServer that manages a single provider's HTTP client with:
  - Circuit breaker (closed/open/half-open states)
  - Rate limiting (token bucket)
  - Retries with exponential backoff

  Each provider has its own ProviderClient process.
  """

  use GenServer

  require Logger

  alias LlmMarket.Orchestrator.{CircuitBreaker, RateLimiter}

  defstruct [
    :provider,
    :config,
    :circuit_breaker,
    :rate_limiter
  ]

  # Client API

  def start_link({provider, config}) do
    GenServer.start_link(__MODULE__, {provider, config}, name: via_tuple(provider))
  end

  def via_tuple(provider) do
    {:via, Registry, {LlmMarket.Orchestrator.Registry, provider}}
  end

  @doc """
  Make a call to the provider.
  """
  def call(provider, prompt, opts \\ []) do
    GenServer.call(via_tuple(provider), {:call, prompt, opts}, :infinity)
  catch
    :exit, {:noproc, _} ->
      {:error, %{type: :provider_not_started, message: "Provider #{provider} is not running"}}
  end

  @doc """
  Get the current state of the provider client (for health checks).
  """
  def get_state(provider) do
    GenServer.call(via_tuple(provider), :get_state)
  catch
    :exit, {:noproc, _} ->
      %{circuit: :unknown}
  end

  # Server callbacks

  @impl true
  def init({provider, config}) do
    state = %__MODULE__{
      provider: provider,
      config: config,
      circuit_breaker: CircuitBreaker.new(
        provider: provider,
        failure_threshold: 3,
        recovery_timeout: 30_000
      ),
      rate_limiter: RateLimiter.new(config[:rate_limit] || {10, :per_second})
    }

    Logger.info("Started ProviderClient for #{provider}")
    {:ok, state}
  end

  @impl true
  def handle_call({:call, prompt, opts}, _from, state) do
    {result, new_state} = do_call(state, prompt, opts)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      provider: state.provider,
      circuit: state.circuit_breaker.state,
      rate_limiter_tokens: state.rate_limiter.tokens
    }

    {:reply, info, state}
  end

  defp do_call(state, prompt, opts) do
    # Check circuit breaker
    case CircuitBreaker.allow?(state.circuit_breaker) do
      {:ok, cb} ->
        state = %{state | circuit_breaker: cb}

        # Check rate limiter
        case RateLimiter.acquire(state.rate_limiter) do
          {:ok, rl} ->
            state = %{state | rate_limiter: rl}
            execute_with_retry(state, prompt, opts)

          {:error, :rate_limited} ->
            {{:error, %{type: :rate_limited, message: "Rate limited"}}, state}
        end

      {:error, :circuit_open} ->
        {{:error, %{type: :circuit_open, message: "Circuit breaker is open"}}, state}
    end
  end

  defp execute_with_retry(state, prompt, opts, attempt \\ 1) do
    max_retries = state.config[:max_retries] || LlmMarket.market_config()[:max_retries] || 2
    timeout = state.config[:timeout_ms] || LlmMarket.market_config()[:provider_timeout_ms] || 25_000

    model = opts[:model] || state.config[:default_model]
    start_time = System.monotonic_time(:millisecond)

    # Get the adapter module for this provider
    adapter = get_adapter(state.provider)

    Logger.info("Calling provider #{state.provider} with model #{model}")
    result = adapter.call(prompt, Keyword.merge(opts, model: model, timeout: timeout))
    Logger.info("Provider #{state.provider} result: #{inspect(result, limit: 200)}")

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, response} ->
        # Success - record and close circuit
        cb = CircuitBreaker.record_success(state.circuit_breaker)
        state = %{state | circuit_breaker: cb}

        normalized = adapter.normalize(response)
        normalized = Map.put(normalized, :latency_ms, duration)

        {{:ok, normalized}, state}

      {:error, %{http_status: status} = error} when status in [429, 500, 502, 503, 504] ->
        # Retryable error
        if attempt <= max_retries do
          backoff = :math.pow(2, attempt) * 1000 |> trunc()
          Process.sleep(backoff)
          execute_with_retry(state, prompt, opts, attempt + 1)
        else
          cb = CircuitBreaker.record_failure(state.circuit_breaker)
          state = %{state | circuit_breaker: cb}
          {{:error, Map.put(error, :latency_ms, duration)}, state}
        end

      {:error, error} ->
        # Non-retryable error
        cb = CircuitBreaker.record_failure(state.circuit_breaker)
        state = %{state | circuit_breaker: cb}
        {{:error, Map.put(error, :latency_ms, duration)}, state}
    end
  end

  defp get_adapter(:openai), do: LlmMarket.Providers.OpenAI
  defp get_adapter(:anthropic), do: LlmMarket.Providers.Anthropic
  defp get_adapter(:gemini), do: LlmMarket.Providers.Gemini
end
