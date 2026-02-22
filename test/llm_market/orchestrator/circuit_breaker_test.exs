defmodule LlmMarket.Orchestrator.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias LlmMarket.Orchestrator.CircuitBreaker

  describe "new/1" do
    test "creates circuit breaker in closed state" do
      cb = CircuitBreaker.new()

      assert cb.state == :closed
      assert cb.failure_count == 0
      assert cb.failure_threshold == 3
    end

    test "accepts custom configuration" do
      cb = CircuitBreaker.new(failure_threshold: 5, recovery_timeout: 60_000)

      assert cb.failure_threshold == 5
      assert cb.recovery_timeout == 60_000
    end
  end

  describe "allow?/1" do
    test "allows requests when closed" do
      cb = CircuitBreaker.new()
      assert {:ok, ^cb} = CircuitBreaker.allow?(cb)
    end

    test "blocks requests when open" do
      cb = %CircuitBreaker{
        state: :open,
        failure_count: 3,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        last_failure_time: System.monotonic_time(:millisecond)
      }

      assert {:error, :circuit_open} = CircuitBreaker.allow?(cb)
    end

    test "transitions to half-open after recovery timeout" do
      cb = %CircuitBreaker{
        state: :open,
        failure_count: 3,
        failure_threshold: 3,
        recovery_timeout: 1,
        last_failure_time: System.monotonic_time(:millisecond) - 10
      }

      assert {:ok, new_cb} = CircuitBreaker.allow?(cb)
      assert new_cb.state == :half_open
    end

    test "allows requests when half-open" do
      cb = %CircuitBreaker{
        state: :half_open,
        failure_count: 0,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        last_failure_time: nil
      }

      assert {:ok, ^cb} = CircuitBreaker.allow?(cb)
    end
  end

  describe "record_success/1" do
    test "resets failure count when closed" do
      cb = %CircuitBreaker{
        state: :closed,
        failure_count: 2,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        last_failure_time: nil
      }

      new_cb = CircuitBreaker.record_success(cb)
      assert new_cb.failure_count == 0
    end

    test "transitions to closed when half-open" do
      cb = %CircuitBreaker{
        state: :half_open,
        failure_count: 0,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        last_failure_time: nil
      }

      new_cb = CircuitBreaker.record_success(cb)
      assert new_cb.state == :closed
      assert new_cb.failure_count == 0
    end
  end

  describe "record_failure/1" do
    test "increments failure count when closed" do
      cb = CircuitBreaker.new()

      new_cb = CircuitBreaker.record_failure(cb)
      assert new_cb.failure_count == 1
      assert new_cb.state == :closed
    end

    test "opens circuit after reaching threshold" do
      cb = %CircuitBreaker{
        state: :closed,
        failure_count: 2,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        last_failure_time: nil
      }

      new_cb = CircuitBreaker.record_failure(cb)
      assert new_cb.state == :open
      assert new_cb.failure_count == 3
      assert new_cb.last_failure_time != nil
    end

    test "stays open and updates timestamp when already open" do
      old_time = System.monotonic_time(:millisecond) - 1000

      cb = %CircuitBreaker{
        state: :open,
        failure_count: 3,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        last_failure_time: old_time
      }

      new_cb = CircuitBreaker.record_failure(cb)
      assert new_cb.state == :open
      assert new_cb.last_failure_time > old_time
    end

    test "reopens circuit when half-open" do
      cb = %CircuitBreaker{
        state: :half_open,
        failure_count: 0,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        last_failure_time: nil
      }

      new_cb = CircuitBreaker.record_failure(cb)
      assert new_cb.state == :open
    end
  end
end
