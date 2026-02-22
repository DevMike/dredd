defmodule LlmMarket.Core.Dredd do
  @moduledoc """
  Dredd (arbiter) logic for synthesizing final answers.

  Implements the fallback chain:
  1. Primary dredd (chat-specific or default)
  2. Retry once
  3. Fallback dredd
  4. Best single response
  """

  require Logger

  alias LlmMarket.Core.Prompts
  alias LlmMarket.Orchestrator.ProviderClient
  alias LlmMarket.Providers.Base
  alias LlmMarket.Schemas.DreddOutput

  @doc """
  Run the dredd step with fallback chain.

  Returns {:ok, dredd_output} or {:error, :all_dredds_failed, best_response}
  """
  def run(run_id, question, responses, num_rounds, opts \\ []) do
    {primary_provider, primary_model} = get_primary_dredd(opts)
    {fallback_provider, fallback_model} = get_fallback_dredd()

    prompt = Prompts.dredd(question, responses, num_rounds)

    # Try primary dredd
    case call_dredd(primary_provider, primary_model, prompt) do
      {:ok, result, latency, cost} ->
        {:ok, build_output(run_id, primary_provider, primary_model, result, latency, cost)}

      {:error, _reason} ->
        Logger.warning("Primary dredd failed, retrying...")

        # Retry once
        case call_dredd(primary_provider, primary_model, prompt) do
          {:ok, result, latency, cost} ->
            {:ok, build_output(run_id, primary_provider, primary_model, result, latency, cost)}

          {:error, _reason} ->
            Logger.warning("Primary dredd retry failed, trying fallback...")

            # Try fallback dredd
            case call_dredd(fallback_provider, fallback_model, prompt) do
              {:ok, result, latency, cost} ->
                {:ok,
                 build_output(run_id, fallback_provider, fallback_model, result, latency, cost)}

              {:error, _reason} ->
                Logger.error("All dredds failed, returning best single response")

                best = find_best_response(responses)

                {:error, :all_dredds_failed, best,
                 DreddOutput.failed(run_id, primary_provider, primary_model, 0)}
            end
        end
    end
  end

  defp call_dredd(provider, model, prompt) do
    start_time = System.monotonic_time(:millisecond)

    result = ProviderClient.call(provider, prompt, model: model)
    latency = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, normalized} ->
        # Parse the dredd response
        case parse_dredd_response(normalized) do
          {:ok, parsed} ->
            cost = normalized[:usage][:cost_usd]
            {:ok, parsed, latency, cost}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp parse_dredd_response(normalized) do
    raw = normalized[:raw_response] || normalized[:answer]

    case Base.parse_llm_json(raw) do
      {:ok, parsed} when is_map(parsed) ->
        # Validate required fields
        if Map.has_key?(parsed, "final_answer") do
          {:ok, parsed}
        else
          {:error, :missing_final_answer}
        end

      {:ok, _} ->
        {:error, :invalid_response_format}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_output(run_id, provider, model, parsed, latency, cost) do
    DreddOutput.from_parsed(run_id, provider, model, parsed, latency, cost)
  end

  defp find_best_response(responses) do
    # Find response with highest confidence
    responses
    |> Enum.max_by(
      fn {_provider, _model, response} ->
        response[:confidence] || 0
      end,
      fn -> nil end
    )
  end

  defp get_primary_dredd(opts) do
    case opts[:dredd] do
      {provider, model} -> {provider, model}
      _ -> LlmMarket.dredd_config()[:default]
    end
  end

  defp get_fallback_dredd do
    LlmMarket.dredd_config()[:fallback] || {:openai, "gpt-4o"}
  end
end
