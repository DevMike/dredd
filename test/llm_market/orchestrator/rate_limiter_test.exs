defmodule LlmMarket.Orchestrator.RateLimiterTest do
  use ExUnit.Case, async: true

  alias LlmMarket.Orchestrator.RateLimiter

  describe "new/1" do
    test "creates limiter with correct initial state" do
      limiter = RateLimiter.new({10, :per_second})

      assert limiter.tokens == 10
      assert limiter.max_tokens == 10
      assert limiter.refill_rate == 10
      assert limiter.refill_interval == 1_000
    end

    test "supports per_minute interval" do
      limiter = RateLimiter.new({100, :per_minute})

      assert limiter.refill_interval == 60_000
    end

    test "supports custom interval in ms" do
      limiter = RateLimiter.new({5, 500})

      assert limiter.refill_interval == 500
    end
  end

  describe "acquire/1" do
    test "succeeds when tokens available" do
      limiter = RateLimiter.new({10, :per_second})

      assert {:ok, new_limiter} = RateLimiter.acquire(limiter)
      assert new_limiter.tokens < limiter.tokens
    end

    test "fails when no tokens available" do
      limiter = %RateLimiter{
        tokens: 0,
        max_tokens: 10,
        refill_rate: 10,
        refill_interval: 1_000,
        last_refill: System.monotonic_time(:millisecond)
      }

      assert {:error, :rate_limited} = RateLimiter.acquire(limiter)
    end

    test "refills tokens after interval" do
      limiter = %RateLimiter{
        tokens: 0,
        max_tokens: 10,
        refill_rate: 10,
        refill_interval: 1,
        last_refill: System.monotonic_time(:millisecond) - 2
      }

      # Should refill after waiting
      assert {:ok, _new_limiter} = RateLimiter.acquire(limiter)
    end
  end

  describe "available?/1" do
    test "returns true when tokens available" do
      limiter = RateLimiter.new({10, :per_second})
      assert RateLimiter.available?(limiter) == true
    end

    test "returns false when no tokens" do
      limiter = %RateLimiter{
        tokens: 0,
        max_tokens: 10,
        refill_rate: 10,
        refill_interval: 60_000,
        last_refill: System.monotonic_time(:millisecond)
      }

      assert RateLimiter.available?(limiter) == false
    end
  end

  describe "tokens/1" do
    test "returns current token count" do
      limiter = RateLimiter.new({10, :per_second})
      assert RateLimiter.tokens(limiter) == 10
    end
  end
end
