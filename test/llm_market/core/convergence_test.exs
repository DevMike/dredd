defmodule LlmMarket.Core.ConvergenceTest do
  use ExUnit.Case, async: true

  alias LlmMarket.Core.Convergence

  describe "calculate_confidence_delta/1" do
    test "returns 0 for single value" do
      assert Convergence.calculate_confidence_delta([0.8]) == 0.0
    end

    test "returns difference for two values" do
      assert_in_delta Convergence.calculate_confidence_delta([0.8, 0.6]), 0.2, 0.001
    end

    test "returns max difference for multiple values" do
      assert Convergence.calculate_confidence_delta([0.8, 0.6, 0.9, 0.5]) == 0.4
    end

    test "handles nil values" do
      assert_in_delta Convergence.calculate_confidence_delta([0.8, nil, 0.6]), 0.2, 0.001
    end

    test "returns 1.0 for empty list" do
      assert Convergence.calculate_confidence_delta([]) == 1.0
    end
  end

  describe "jaccard/2" do
    test "returns 1.0 for identical sets" do
      set = MapSet.new(["a", "b", "c"])
      assert Convergence.jaccard(set, set) == 1.0
    end

    test "returns 0.0 for disjoint sets" do
      set_a = MapSet.new(["a", "b"])
      set_b = MapSet.new(["c", "d"])
      assert Convergence.jaccard(set_a, set_b) == 0.0
    end

    test "returns correct value for overlapping sets" do
      set_a = MapSet.new(["a", "b", "c"])
      set_b = MapSet.new(["b", "c", "d"])
      # Intersection: {b, c} = 2, Union: {a, b, c, d} = 4
      assert Convergence.jaccard(set_a, set_b) == 0.5
    end

    test "returns 1.0 for empty sets" do
      set = MapSet.new([])
      assert Convergence.jaccard(set, set) == 1.0
    end
  end

  describe "calculate_claim_overlap/1" do
    test "returns 1.0 for single response" do
      claims = [["claim a", "claim b"]]
      assert Convergence.calculate_claim_overlap(claims) == 1.0
    end

    test "returns 1.0 for identical claims" do
      claims = [
        ["claim a", "claim b"],
        ["claim a", "claim b"]
      ]

      assert Convergence.calculate_claim_overlap(claims) == 1.0
    end

    test "returns 0.0 for completely different claims" do
      claims = [
        ["claim a", "claim b"],
        ["claim c", "claim d"]
      ]

      assert Convergence.calculate_claim_overlap(claims) == 0.0
    end

    test "handles nil claims" do
      claims = [["claim a"], nil, ["claim a"]]
      assert Convergence.calculate_claim_overlap(claims) == 1.0
    end

    test "returns 0.0 for empty list" do
      assert Convergence.calculate_claim_overlap([]) == 0.0
    end
  end

  describe "check/2" do
    test "returns converged when both thresholds met" do
      responses = [
        {:openai, "gpt-4o", %{confidence: 0.85, key_claims: ["a", "b"]}},
        {:anthropic, "claude", %{confidence: 0.82, key_claims: ["a", "b"]}}
      ]

      {converged, _metrics} =
        Convergence.check(responses,
          confidence_threshold: 0.1,
          overlap_threshold: 0.7
        )

      assert converged == true
    end

    test "returns not converged when confidence delta too high" do
      responses = [
        {:openai, "gpt-4o", %{confidence: 0.9, key_claims: ["a", "b"]}},
        {:anthropic, "claude", %{confidence: 0.5, key_claims: ["a", "b"]}}
      ]

      {converged, metrics} =
        Convergence.check(responses,
          confidence_threshold: 0.1,
          overlap_threshold: 0.7
        )

      assert converged == false
      assert metrics.confidence_delta == 0.4
    end

    test "returns not converged when claim overlap too low" do
      responses = [
        {:openai, "gpt-4o", %{confidence: 0.85, key_claims: ["a", "b"]}},
        {:anthropic, "claude", %{confidence: 0.82, key_claims: ["c", "d"]}}
      ]

      {converged, metrics} =
        Convergence.check(responses,
          confidence_threshold: 0.1,
          overlap_threshold: 0.7
        )

      assert converged == false
      assert metrics.claim_overlap == 0.0
    end
  end

  describe "detect_disagreements/1" do
    test "returns empty list when no conflicts" do
      responses = [
        {:openai, "gpt-4o", %{key_claims: ["same claim"]}},
        {:anthropic, "claude", %{key_claims: ["same claim"]}}
      ]

      assert Convergence.detect_disagreements(responses) == []
    end

    test "handles nil claims" do
      responses = [
        {:openai, "gpt-4o", %{key_claims: nil}},
        {:anthropic, "claude", %{key_claims: ["claim"]}}
      ]

      assert Convergence.detect_disagreements(responses) == []
    end
  end
end
