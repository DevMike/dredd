defmodule LlmMarket.Telegram.Formatter do
  @moduledoc """
  Format responses for Telegram display.
  Uses plain text for reliability.
  """

  @max_message_length 4096

  @doc """
  Format a run result for display.
  """
  def format_run_result(run) do
    dredd = run.dredd_output

    if dredd && !dredd.dredd_failed do
      answer = dredd.final_answer |> format_numbered_list() |> truncate(2500)

      """
      📋 ANSWER

      #{answer}

      ✅ Confidence: #{format_confidence(dredd.overall_confidence)}
      🔄 Rounds: #{run.rounds_completed} completed
      """
    else
      format_fallback_result(run)
    end
    |> truncate(@max_message_length)
  end

  defp format_fallback_result(run) do
    """
    ⚠️ PARTIAL RESULT (dredd failed)

    Unable to synthesize responses. Use /raw #{run.id} to see individual answers.

    🔄 Rounds: #{run.rounds_completed} completed
    """
  end

  @doc """
  Format raw provider answers.
  Returns a list of messages - one header + one per round with all providers.
  """
  def format_raw_answers(run) do
    grouped = run.provider_answers |> Enum.group_by(& &1.round)
    total_rounds = grouped |> Map.keys() |> length()

    # Build messages for each round
    messages =
      grouped
      |> Enum.sort_by(fn {round, _} -> round end)
      |> Enum.flat_map(fn {round, answers} ->
        round_header = "📝 ROUND #{round} of #{total_rounds}\n\n"

        provider_messages =
          answers
          |> Enum.map(fn a ->
            status_str = a.status |> to_string()
            status = if status_str == "ok", do: "", else: " (#{status_str})"
            answer = (a.answer || "") |> format_numbered_list() |> truncate(3500)

            """
            🤖 #{a.provider} (#{a.model || "unknown"})#{status}
            Confidence: #{format_confidence(a.confidence)}

            #{answer}
            """
          end)

        [round_header | provider_messages]
      end)

    messages
  end

  @doc """
  Format conflicts.
  """
  def format_conflicts(run) do
    case run.dredd_output do
      nil ->
        "No dredd output available."

      dredd ->
        conflicts = extract_conflicts(dredd.conflicts)

        if Enum.empty?(conflicts) do
          "✅ No conflicts detected."
        else
          header = "⚔️ CONFLICTS\n\n"

          conflict_text =
            conflicts
            |> Enum.map(fn conflict ->
              claims =
                (conflict["claims"] || [])
                |> Enum.map(fn c -> "  • #{c["provider"]}: #{c["claim"]}" end)
                |> Enum.join("\n")

              """
              📌 #{conflict["topic"] || "Unknown"} [#{conflict["status"] || "unknown"}]
              #{claims}
              ➡️ Resolution: #{conflict["resolution"] || "None"}
              """
            end)
            |> Enum.join("\n---\n")

          truncate(header <> conflict_text, @max_message_length)
        end
    end
  end

  # Extract conflicts from various possible formats
  defp extract_conflicts(nil), do: []
  defp extract_conflicts([]), do: []
  defp extract_conflicts(list) when is_list(list), do: list
  defp extract_conflicts(%{items: items}) when is_list(items), do: items
  defp extract_conflicts(%{"items" => items}) when is_list(items), do: items
  defp extract_conflicts(_), do: []

  @doc """
  Format providers list.
  """
  def format_providers(providers) do
    if map_size(providers) == 0 do
      "No providers configured. Check your API keys."
    else
      provider_list =
        providers
        |> Enum.map(fn {name, config} ->
          models = Enum.join(config[:models] || [], ", ")
          default = config[:default_model]
          "• #{name}: #{models} (default: #{default})"
        end)
        |> Enum.join("\n")

      "🔧 ENABLED PROVIDERS\n\n#{provider_list}"
    end
  end

  @doc """
  Format config display.
  """
  def format_config(thread) do
    dredd =
      if thread.default_dredd_provider do
        "#{thread.default_dredd_provider}:#{thread.default_dredd_model}"
      else
        {provider, model} = LlmMarket.dredd_config()[:default]
        "#{provider}:#{model} (default)"
      end

    market = LlmMarket.market_config()

    """
    ⚙️ CURRENT CONFIGURATION

    Dredd: #{dredd}
    Max rounds: #{market[:max_rounds]}
    Timeout: #{market[:provider_timeout_ms]}ms
    """
  end

  @doc """
  Format cost breakdown.
  """
  def format_cost_breakdown(run) do
    total_cost = to_float(run.total_cost_usd) || 0.0
    total_latency = run.total_latency_ms || 0

    # Group answers by provider
    grouped = Enum.group_by(run.provider_answers, & &1.provider)

    breakdown =
      grouped
      |> Enum.sort_by(fn {provider, _} -> provider end)
      |> Enum.map(fn {provider, answers} ->
        # Per-round details
        rounds =
          answers
          |> Enum.sort_by(& &1.round)
          |> Enum.map(fn a ->
            cost = extract_cost(a.usage)
            "  R#{a.round}: #{a.latency_ms || 0}ms, #{cost}"
          end)
          |> Enum.join("\n")

        # Provider totals
        provider_latency = answers |> Enum.map(& &1.latency_ms || 0) |> Enum.sum()
        provider_cost = answers |> Enum.map(&extract_cost_float(&1.usage)) |> Enum.sum()

        """
        🤖 #{provider}
        #{rounds}
          Total: #{provider_latency}ms, $#{Float.round(provider_cost, 4)}
        """
      end)
      |> Enum.join("\n")

    dredd_section =
      if run.dredd_output do
        dredd_cost = if run.dredd_output.cost_usd, do: "$#{Float.round(to_float(run.dredd_output.cost_usd), 4)}", else: "N/A"
        dredd_provider = run.dredd_output.dredd_provider || "unknown"
        dredd_model = run.dredd_output.dredd_model || ""
        """
        ⚖️ dredd (#{dredd_provider}:#{dredd_model})
          #{run.dredd_output.latency_ms || 0}ms, #{dredd_cost}
        """
      else
        ""
      end

    """
    💰 COST & LATENCY BREAKDOWN

    #{breakdown}
    #{dredd_section}
    📊 TOTAL: #{total_latency}ms, $#{Float.round(total_cost, 4)}
    """
  end

  defp extract_cost(nil), do: "N/A"
  defp extract_cost(usage) do
    cond do
      usage["cost_usd"] -> "$#{Float.round(to_float(usage["cost_usd"]), 4)}"
      usage[:cost_usd] -> "$#{Float.round(to_float(usage[:cost_usd]), 4)}"
      true -> "N/A"
    end
  end

  defp extract_cost_float(nil), do: 0.0
  defp extract_cost_float(usage) do
    cond do
      usage["cost_usd"] -> to_float(usage["cost_usd"])
      usage[:cost_usd] -> to_float(usage[:cost_usd])
      true -> 0.0
    end
  end

  @doc """
  Format an error for display.
  """
  def format_error(:all_providers_failed) do
    "❌ Unable to get responses from any provider. Please try again later."
  end

  def format_error(:rate_limited) do
    "⏳ Too many requests. Please wait a moment and try again."
  end

  def format_error(:cancelled) do
    "🚫 Request cancelled."
  end

  def format_error(reason) when is_binary(reason) do
    "❌ Error: #{reason}"
  end

  def format_error(_) do
    "❌ An unexpected error occurred. Please try again."
  end

  # Helpers

  defp format_confidence(nil), do: "N/A"
  defp format_confidence(%Decimal{} = conf), do: "#{conf |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()}%"
  defp format_confidence(conf) when is_number(conf), do: "#{round(conf * 100)}%"

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(f) when is_float(f), do: f
  defp to_float(i) when is_integer(i), do: i * 1.0
  defp to_float(_), do: 0.0

  defp truncate(nil, _), do: ""
  defp truncate(text, max_length) when byte_size(text) <= max_length, do: text

  defp truncate(text, max_length) do
    String.slice(text, 0, max_length - 3) <> "..."
  end

  # Format numbered lists by adding line breaks before numbers
  defp format_numbered_list(nil), do: ""
  defp format_numbered_list(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+(\d+)\.\s+/, "\n\n\\1. ")
    |> String.trim_leading("\n")
  end
  defp format_numbered_list(text), do: to_string(text)
end
