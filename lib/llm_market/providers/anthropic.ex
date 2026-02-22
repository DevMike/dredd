defmodule LlmMarket.Providers.Anthropic do
  @moduledoc """
  Anthropic provider adapter.

  Uses the Messages API.
  """

  @behaviour LlmMarket.Providers.Behaviour

  alias LlmMarket.Providers.{Base, CostCalculator}

  @default_model "claude-sonnet-4-20250514"
  @api_version "2023-06-01"

  @impl true
  def call(prompt, opts \\ []) do
    model = opts[:model] || @default_model
    timeout = opts[:timeout] || 30_000

    api_key = get_api_key()

    if is_nil(api_key) do
      {:error,
       %{type: :config_error, message: "Anthropic API key not configured", http_status: nil}}
    else
      do_call(prompt, model, api_key, timeout)
    end
  end

  defp do_call(prompt, model, api_key, timeout) do
    url = "https://api.anthropic.com/v1/messages"

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: model,
      max_tokens: 4096,
      messages: [
        %{role: "user", content: prompt}
      ]
    }

    Base.request(:post, url, headers, body, timeout: timeout)
  end

  @impl true
  def normalize(response) do
    content_blocks = response["content"] || []

    # Extract text from content blocks
    content =
      content_blocks
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.join("\n")

    usage = response["usage"]
    model = response["model"]
    stop_reason = response["stop_reason"]

    # Check for safety stops
    status =
      cond do
        stop_reason == "end_turn" -> :ok
        stop_reason == "max_tokens" -> :ok
        stop_reason in ["content_filter", "safety"] -> :safety_block
        true -> :ok
      end

    # Parse the JSON content
    {parsed, parse_error} =
      case Base.parse_llm_json(content) do
        {:ok, parsed} -> {parsed, false}
        {:error, _} -> {%{}, true}
      end

    answer_data = Base.extract_answer(parsed)

    # Calculate cost
    input_tokens = usage["input_tokens"]
    output_tokens = usage["output_tokens"]
    cost = CostCalculator.calculate(model, input_tokens || 0, output_tokens || 0)

    final_status =
      cond do
        status == :safety_block -> "error"
        parse_error -> "parse_error"
        true -> "ok"
      end

    %{
      model: model,
      status: final_status,
      answer: answer_data[:answer] || content,
      confidence: answer_data[:confidence],
      key_claims: answer_data[:key_claims],
      assumptions: answer_data[:assumptions],
      citations: answer_data[:citations],
      usage: %{
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: (input_tokens || 0) + (output_tokens || 0),
        cost_usd: cost
      },
      error:
        if(status == :safety_block,
          do: %{type: "safety_block", message: "Content filtered"},
          else: nil
        ),
      raw_response: content
    }
  end

  @impl true
  def estimate_cost(usage, model) do
    input = usage["input_tokens"] || usage[:input_tokens] || 0
    output = usage["output_tokens"] || usage[:output_tokens] || 0
    CostCalculator.calculate(model, input, output)
  end

  defp get_api_key do
    Application.get_env(:llm_market, :api_keys)[:anthropic]
  end
end
