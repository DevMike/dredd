defmodule LlmMarket.Providers.Gemini do
  @moduledoc """
  Google Gemini provider adapter.

  Uses the generateContent API.
  """

  @behaviour LlmMarket.Providers.Behaviour

  alias LlmMarket.Providers.{Base, CostCalculator}

  @default_model "gemini-2.0-flash"

  @impl true
  def call(prompt, opts \\ []) do
    model = opts[:model] || @default_model
    timeout = opts[:timeout] || 25_000

    api_key = get_api_key()

    if is_nil(api_key) do
      {:error, %{type: :config_error, message: "Gemini API key not configured", http_status: nil}}
    else
      do_call(prompt, model, api_key, timeout)
    end
  end

  defp do_call(prompt, model, api_key, timeout) do
    url =
      "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"

    headers = [
      {"Content-Type", "application/json"}
    ]

    body = %{
      contents: [
        %{
          parts: [%{text: prompt}]
        }
      ],
      generationConfig: %{
        temperature: 0.7,
        responseMimeType: "application/json"
      }
    }

    Base.request(:post, url, headers, body, timeout: timeout)
  end

  @impl true
  def normalize(response) do
    candidates = response["candidates"] || []
    candidate = List.first(candidates)

    # Check for blocked responses
    if is_nil(candidate) || blocked?(candidate) do
      handle_blocked(response)
    else
      handle_success(candidate, response)
    end
  end

  defp blocked?(candidate) do
    finish_reason = candidate["finishReason"]
    finish_reason in ["SAFETY", "RECITATION", "OTHER"]
  end

  defp handle_blocked(response) do
    block_reason = get_in(response, ["promptFeedback", "blockReason"]) || "UNKNOWN"

    %{
      model: nil,
      status: "error",
      answer: nil,
      confidence: nil,
      error: %{
        type: "safety_block",
        message: "Response blocked: #{block_reason}"
      }
    }
  end

  defp handle_success(candidate, response) do
    content =
      candidate
      |> get_in(["content", "parts"])
      |> List.wrap()
      |> Enum.map(& &1["text"])
      |> Enum.join("\n")

    usage = response["usageMetadata"]
    model = response["modelVersion"]

    # Parse the JSON content
    {parsed, parse_error} =
      case Base.parse_llm_json(content) do
        {:ok, parsed} -> {parsed, false}
        {:error, _} -> {%{}, true}
      end

    answer_data = Base.extract_answer(parsed)

    # Calculate cost
    input_tokens = usage["promptTokenCount"]
    output_tokens = usage["candidatesTokenCount"]
    cost = CostCalculator.calculate(model || @default_model, input_tokens || 0, output_tokens || 0)

    %{
      model: model || @default_model,
      status: if(parse_error, do: "parse_error", else: "ok"),
      answer: answer_data[:answer] || content,
      confidence: answer_data[:confidence],
      key_claims: answer_data[:key_claims],
      assumptions: answer_data[:assumptions],
      citations: answer_data[:citations],
      usage: %{
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: usage["totalTokenCount"],
        cost_usd: cost
      },
      raw_response: content
    }
  end

  @impl true
  def estimate_cost(usage, model) do
    input = usage["input_tokens"] || usage[:input_tokens] || usage["promptTokenCount"] || 0
    output = usage["output_tokens"] || usage[:output_tokens] || usage["candidatesTokenCount"] || 0
    CostCalculator.calculate(model, input, output)
  end

  defp get_api_key do
    Application.get_env(:llm_market, :api_keys)[:gemini]
  end
end
