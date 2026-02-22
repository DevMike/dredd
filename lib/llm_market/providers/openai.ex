defmodule LlmMarket.Providers.OpenAI do
  @moduledoc """
  OpenAI provider adapter.

  Uses the Chat Completions API with JSON mode.
  """

  @behaviour LlmMarket.Providers.Behaviour

  alias LlmMarket.Providers.{Base, CostCalculator}

  @default_model "gpt-4o"

  require Logger

  @impl true
  def call(prompt, opts \\ []) do
    model = opts[:model] || @default_model
    timeout = opts[:timeout] || 25_000

    api_key = get_api_key()
    Logger.info("OpenAI API key present: #{not is_nil(api_key)}, length: #{if api_key, do: String.length(api_key), else: 0}")

    if is_nil(api_key) do
      {:error, %{type: :config_error, message: "OpenAI API key not configured", http_status: nil}}
    else
      do_call(prompt, model, api_key, timeout)
    end
  end

  defp do_call(prompt, model, api_key, timeout) do
    url = "https://api.openai.com/v1/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: model,
      messages: [
        %{role: "user", content: prompt}
      ],
      response_format: %{type: "json_object"},
      temperature: 0.7
    }

    Base.request(:post, url, headers, body, timeout: timeout)
  end

  @impl true
  def normalize(response) do
    choice = List.first(response["choices"] || [])
    content = get_in(choice, ["message", "content"]) || ""
    usage = response["usage"]
    model = response["model"]

    # Parse the JSON content
    {parsed, parse_error} =
      case Base.parse_llm_json(content) do
        {:ok, parsed} -> {parsed, false}
        {:error, _} -> {%{}, true}
      end

    answer_data = Base.extract_answer(parsed)

    # Calculate cost
    input_tokens = usage["prompt_tokens"]
    output_tokens = usage["completion_tokens"]
    cost = CostCalculator.calculate(model, input_tokens || 0, output_tokens || 0)

    %{
      model: model,
      status: if(parse_error, do: "parse_error", else: "ok"),
      answer: answer_data[:answer] || content,
      confidence: answer_data[:confidence],
      key_claims: answer_data[:key_claims],
      assumptions: answer_data[:assumptions],
      citations: answer_data[:citations],
      usage: %{
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: usage["total_tokens"],
        cost_usd: cost
      },
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
    Application.get_env(:llm_market, :api_keys)[:openai]
  end
end
