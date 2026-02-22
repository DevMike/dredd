defmodule LlmMarket.Core.Convergence do
  @moduledoc """
  Convergence calculation for the market loop.

  Determines when models have reached sufficient agreement to stop iterating.
  """

  @doc """
  Check if responses have converged based on:
  1. Confidence delta <= threshold
  2. Claim overlap >= threshold

  Returns {converged?, metrics}
  """
  def check(responses, opts \\ []) do
    confidence_threshold = opts[:confidence_threshold] || 0.1
    overlap_threshold = opts[:overlap_threshold] || 0.7

    confidences = extract_confidences(responses)
    claims = extract_claims(responses)

    confidence_delta = calculate_confidence_delta(confidences)
    claim_overlap = calculate_claim_overlap(claims)

    converged =
      confidence_delta <= confidence_threshold &&
        claim_overlap >= overlap_threshold

    metrics = %{
      confidence_delta: confidence_delta,
      claim_overlap: claim_overlap,
      confidence_threshold: confidence_threshold,
      overlap_threshold: overlap_threshold
    }

    {converged, metrics}
  end

  @doc """
  Calculate the maximum difference between any two confidence values.
  """
  def calculate_confidence_delta(confidences) do
    # Filter out nil values
    valid = Enum.reject(confidences, &is_nil/1)

    case valid do
      [] -> 1.0
      [_] -> 0.0
      _ -> Enum.max(valid) - Enum.min(valid)
    end
  end

  @doc """
  Calculate average pairwise Jaccard similarity of claims.
  """
  def calculate_claim_overlap(claims_list) do
    # Filter out nil/empty claim lists
    valid_claims =
      claims_list
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&Enum.empty?/1)
      |> Enum.map(&normalize_claims/1)
      |> Enum.map(&MapSet.new/1)

    case valid_claims do
      [] ->
        0.0

      [_] ->
        1.0

      sets ->
        # Calculate pairwise Jaccard similarities
        pairs = for a <- sets, b <- sets, a != b, do: {a, b}

        if Enum.empty?(pairs) do
          1.0
        else
          similarities = Enum.map(pairs, fn {a, b} -> jaccard(a, b) end)
          Enum.sum(similarities) / length(similarities)
        end
    end
  end

  @doc """
  Calculate Jaccard similarity between two sets.
  J(A,B) = |A ∩ B| / |A ∪ B|
  """
  def jaccard(set_a, set_b) do
    intersection = MapSet.intersection(set_a, set_b) |> MapSet.size()
    union = MapSet.union(set_a, set_b) |> MapSet.size()

    if union == 0, do: 1.0, else: intersection / union
  end

  @doc """
  Detect disagreements between responses for Round 2 prompts.
  Returns a list of {topic, [{provider, claim}]} tuples.
  """
  def detect_disagreements(responses) do
    # Group claims by normalized form and detect conflicts
    claim_map =
      responses
      |> Enum.flat_map(fn {provider, _model, response} ->
        claims = response[:key_claims] || []

        Enum.map(claims, fn claim ->
          {normalize_claim(claim), provider, claim}
        end)
      end)
      |> Enum.group_by(
        fn {normalized, _provider, _claim} -> normalized end,
        fn {_normalized, provider, claim} -> {provider, claim} end
      )

    # Find topics where providers disagree
    # This is a simplified heuristic - looking for similar topics with different claims
    claim_map
    |> Enum.filter(fn {_topic, positions} ->
      # Only include if there are multiple different claims
      unique_claims =
        positions
        |> Enum.map(fn {_provider, claim} -> normalize_claim(claim) end)
        |> Enum.uniq()

      length(unique_claims) > 1
    end)
    |> Enum.map(fn {topic, positions} -> {topic, positions} end)
    |> Enum.take(5)
  end

  # Private helpers

  defp extract_confidences(responses) do
    Enum.map(responses, fn {_provider, _model, response} ->
      response[:confidence]
    end)
  end

  defp extract_claims(responses) do
    Enum.map(responses, fn {_provider, _model, response} ->
      response[:key_claims]
    end)
  end

  defp normalize_claims(claims) do
    Enum.map(claims, &normalize_claim/1)
  end

  defp normalize_claim(claim) when is_binary(claim) do
    claim
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.trim()
  end

  defp normalize_claim(_), do: ""
end
