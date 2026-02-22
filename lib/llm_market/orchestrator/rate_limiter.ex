defmodule LlmMarket.Orchestrator.RateLimiter do
  @moduledoc """
  Token bucket rate limiter.

  Refills tokens at a constant rate up to max capacity.
  Each request consumes one token.
  """

  defstruct [
    :tokens,
    :max_tokens,
    :refill_rate,
    :refill_interval,
    :last_refill
  ]

  @doc """
  Create a new rate limiter.

  ## Examples

      RateLimiter.new({10, :per_second})  # 10 requests per second
      RateLimiter.new({100, :per_minute}) # 100 requests per minute
  """
  def new({max_tokens, interval}) do
    refill_interval =
      case interval do
        :per_second -> 1_000
        :per_minute -> 60_000
        :per_hour -> 3_600_000
        ms when is_integer(ms) -> ms
      end

    %__MODULE__{
      tokens: max_tokens,
      max_tokens: max_tokens,
      refill_rate: max_tokens,
      refill_interval: refill_interval,
      last_refill: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Try to acquire a token. Returns {:ok, updated_limiter} or {:error, :rate_limited}.
  """
  def acquire(%__MODULE__{} = limiter) do
    limiter = refill(limiter)

    if limiter.tokens >= 1 do
      {:ok, %{limiter | tokens: limiter.tokens - 1}}
    else
      {:error, :rate_limited}
    end
  end

  @doc """
  Check if a token is available without consuming it.
  """
  def available?(%__MODULE__{} = limiter) do
    limiter = refill(limiter)
    limiter.tokens >= 1
  end

  @doc """
  Get current token count.
  """
  def tokens(%__MODULE__{} = limiter) do
    refill(limiter).tokens
  end

  defp refill(%__MODULE__{} = limiter) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - limiter.last_refill

    if elapsed >= limiter.refill_interval do
      # Full refill
      %{limiter | tokens: limiter.max_tokens, last_refill: now}
    else
      # Partial refill based on elapsed time
      tokens_to_add = elapsed / limiter.refill_interval * limiter.refill_rate
      new_tokens = min(limiter.tokens + tokens_to_add, limiter.max_tokens)
      %{limiter | tokens: new_tokens, last_refill: now}
    end
  end
end
