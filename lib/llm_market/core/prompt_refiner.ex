defmodule LlmMarket.Core.PromptRefiner do
  @moduledoc """
  Refines user questions into better prompts using gpt-4o-mini.

  Takes a user's question and generates an improved version that
  will produce more comprehensive answers from AI models.
  """

  alias LlmMarket.Providers.Base

  @refiner_model "gpt-4o-mini"

  @doc """
  Refine a question into a better prompt.

  Returns {:ok, refined} or {:error, reason}
  """
  def refine(question) do
    prompt = build_refiner_prompt(question)

    case call_openai(prompt) do
      {:ok, refined} -> {:ok, String.trim(refined)}
      {:error, _} = error -> error
    end
  end

  defp build_refiner_prompt(question) do
    """
    You are a prompt refinement assistant. Your task is to improve the user's question
    to get better, more comprehensive answers from AI models.

    Guidelines:
    - Keep the same language as the original question
    - Make the question more specific and detailed
    - Add relevant aspects to explore (history, examples, comparisons, etc.)
    - Don't change the core intent
    - Keep it concise (1-3 sentences max)
    - Return ONLY the refined question, no explanations

    Original question: #{question}

    Refined question:
    """
  end

  defp call_openai(prompt) do
    api_key = get_api_key()

    if is_nil(api_key) do
      {:error, :api_key_missing}
    else
      do_call_openai(prompt, api_key)
    end
  end

  defp do_call_openai(prompt, api_key) do
    url = "https://api.openai.com/v1/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: @refiner_model,
      messages: [
        %{role: "user", content: prompt}
      ],
      temperature: 0.7,
      max_tokens: 500
    }

    case Base.request(:post, url, headers, body, timeout: 15_000) do
      {:ok, response} ->
        extract_content(response)

      {:error, _reason} ->
        {:error, :refinement_failed}
    end
  end

  defp extract_content(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil -> {:error, :empty_response}
      content -> {:ok, content}
    end
  end

  defp get_api_key do
    Application.get_env(:llm_market, :api_keys)[:openai]
  end
end
