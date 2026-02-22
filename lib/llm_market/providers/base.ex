defmodule LlmMarket.Providers.Base do
  @moduledoc """
  Shared functionality for provider adapters.
  """

  require Logger

  @doc """
  Make an HTTP request using Finch.
  """
  def request(method, url, headers, body, opts \\ []) do
    timeout = opts[:timeout] || 25_000

    request =
      Finch.build(
        method,
        url,
        headers,
        body && Jason.encode!(body)
      )

    case Finch.request(request, LlmMarket.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, %{type: :parse_error, message: "Invalid JSON response"}}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        error = parse_error_response(status, body)
        {:error, error}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, %{type: :timeout, message: "Request timed out", http_status: nil}}

      {:error, reason} ->
        {:error, %{type: :network_error, message: inspect(reason), http_status: nil}}
    end
  end

  defp parse_error_response(status, body) do
    message =
      case Jason.decode(body) do
        {:ok, %{"error" => %{"message" => msg}}} -> msg
        {:ok, %{"error" => msg}} when is_binary(msg) -> msg
        _ -> body
      end

    type =
      cond do
        status == 429 -> :rate_limit
        status in 500..599 -> :server_error
        status == 401 -> :auth_error
        status == 403 -> :forbidden
        true -> :api_error
      end

    %{type: type, message: message, http_status: status}
  end

  @doc """
  Parse JSON from LLM response, handling common issues.
  """
  def parse_llm_json(text) when is_binary(text) do
    # Try direct parse first
    case Jason.decode(text) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, _} ->
        # Try extracting from markdown code blocks
        text
        |> extract_json_from_markdown()
        |> try_json_fixes()
    end
  end

  def parse_llm_json(_), do: {:error, :invalid_input}

  defp extract_json_from_markdown(text) do
    # Try to extract JSON from ```json ... ``` blocks
    case Regex.run(~r/```(?:json)?\s*(\{[\s\S]*?\})\s*```/, text) do
      [_, json] -> json
      nil -> text
    end
  end

  defp try_json_fixes(text) do
    # Try various fixes for common LLM JSON issues
    fixes = [
      # Remove trailing commas
      fn t -> Regex.replace(~r/,(\s*[\]}])/, t, "\\1") end,
      # Remove comments
      fn t -> Regex.replace(~r/\/\/[^\n]*/, t, "") end,
      # Fix unquoted keys (simple cases)
      fn t -> t end
    ]

    Enum.reduce_while(fixes, {:error, :parse_error}, fn fix, acc ->
      fixed = fix.(text)

      case Jason.decode(fixed) do
        {:ok, parsed} -> {:halt, {:ok, parsed}}
        {:error, _} -> {:cont, acc}
      end
    end)
  end

  @doc """
  Extract structured answer from parsed JSON.
  """
  def extract_answer(parsed) when is_map(parsed) do
    %{
      answer: parsed["answer"],
      confidence: parse_confidence(parsed["confidence"]),
      key_claims: ensure_list(parsed["key_claims"]),
      assumptions: ensure_list(parsed["assumptions"]),
      citations: ensure_list(parsed["citations"])
    }
  end

  def extract_answer(_), do: %{}

  defp parse_confidence(nil), do: nil
  defp parse_confidence(c) when is_number(c), do: c
  defp parse_confidence(c) when is_binary(c) do
    case Float.parse(c) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp ensure_list(nil), do: nil
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list(_), do: nil
end
