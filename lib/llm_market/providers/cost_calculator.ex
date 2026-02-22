defmodule LlmMarket.Providers.CostCalculator do
  @moduledoc """
  Calculate costs for LLM API usage.

  Prices are in USD per 1K tokens.
  """

  # Prices as of early 2025 - should be updated periodically
  @costs %{
    # OpenAI
    "gpt-4o" => %{input: 0.0025, output: 0.010},
    "gpt-4o-mini" => %{input: 0.00015, output: 0.0006},
    "gpt-4-turbo" => %{input: 0.01, output: 0.03},
    "gpt-4" => %{input: 0.03, output: 0.06},
    "gpt-3.5-turbo" => %{input: 0.0005, output: 0.0015},

    # Anthropic
    "claude-sonnet-4-20250514" => %{input: 0.003, output: 0.015},
    "claude-haiku-4-20250514" => %{input: 0.0008, output: 0.004},
    "claude-opus-4-20250514" => %{input: 0.015, output: 0.075},
    "claude-3-5-sonnet-20241022" => %{input: 0.003, output: 0.015},
    "claude-3-5-haiku-20241022" => %{input: 0.0008, output: 0.004},
    "claude-3-opus-20240229" => %{input: 0.015, output: 0.075},

    # Gemini
    "gemini-2.0-flash" => %{input: 0.0001, output: 0.0004},
    "gemini-2.5-flash" => %{input: 0.00015, output: 0.0006},
    "gemini-2.5-pro" => %{input: 0.00125, output: 0.005},
    "gemini-1.5-pro" => %{input: 0.00125, output: 0.005},
    "gemini-1.5-flash" => %{input: 0.000075, output: 0.0003}
  }

  @doc """
  Calculate cost based on token usage.

  Returns cost in USD or nil if model pricing is unknown.
  """
  def calculate(model, input_tokens, output_tokens)
      when is_binary(model) and is_integer(input_tokens) and is_integer(output_tokens) do
    case get_pricing(model) do
      nil ->
        nil

      %{input: input_rate, output: output_rate} ->
        input_cost = input_tokens / 1000 * input_rate
        output_cost = output_tokens / 1000 * output_rate
        Float.round(input_cost + output_cost, 6)
    end
  end

  def calculate(_, _, _), do: nil

  @doc """
  Get pricing info for a model.
  Supports exact match or prefix match for versioned model names
  (e.g., "gpt-4o-2024-08-06" matches "gpt-4o").
  """
  def get_pricing(model) when is_binary(model) do
    # Try exact match first
    case Map.get(@costs, model) do
      nil -> find_by_prefix(model)
      pricing -> pricing
    end
  end

  def get_pricing(_), do: nil

  defp find_by_prefix(model) do
    # Find a pricing entry where the model starts with a known model name
    # Sort by key length descending to match most specific first
    @costs
    |> Enum.filter(fn {known_model, _} -> String.starts_with?(model, known_model) end)
    |> Enum.sort_by(fn {known_model, _} -> -String.length(known_model) end)
    |> case do
      [{_known_model, pricing} | _] -> pricing
      [] -> nil
    end
  end

  @doc """
  Check if we have pricing for a model.
  """
  def has_pricing?(model) do
    get_pricing(model) != nil
  end

  @doc """
  List all models with known pricing.
  """
  def known_models do
    Map.keys(@costs)
  end
end
