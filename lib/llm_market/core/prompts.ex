defmodule LlmMarket.Core.Prompts do
  @moduledoc """
  Prompt templates for the market process.
  """

  @doc """
  Generate the Round 1 prompt for initial responses.
  """
  def round_1(question) do
    """
    You are participating in a multi-model consensus process. Answer the following question thoroughly and honestly.

    IMPORTANT: Your answer MUST be in the SAME LANGUAGE as the question below.

    Question: #{question}

    Respond with ONLY valid JSON matching this exact schema (no markdown, no explanation):
    {
      "answer": "Your complete answer as a string",
      "confidence": <number 0.0 to 1.0 representing your confidence>,
      "key_claims": ["list", "of", "main", "factual", "claims"],
      "assumptions": ["list", "of", "assumptions", "you", "made"],
      "citations": [{"title": "Source name or null", "url": "URL or null"}]
    }

    Guidelines:
    - confidence: 0.0 = pure guess, 0.5 = uncertain, 0.8 = confident, 0.95+ = very certain
    - key_claims: Extract 3-7 main factual assertions from your answer
    - assumptions: Note any assumptions that if wrong would change your answer
    - citations: Include if you reference specific sources; can be empty array
    """
  end

  @doc """
  Generate the Round 2 prompt with exposure to other responses.
  """
  def round_2(question, own_response, other_responses, disagreements) do
    others_summary = format_other_responses(other_responses)
    disagreements_summary = format_disagreements(disagreements)

    """
    You previously answered a question in a multi-model consensus process. You will now see how other models answered.

    IMPORTANT: Your answer MUST be in the SAME LANGUAGE as the question below.

    ## Question
    #{question}

    ## Your Previous Response
    Answer: #{own_response[:answer]}
    Confidence: #{own_response[:confidence]}
    Key Claims: #{format_claims(own_response[:key_claims])}

    ## Other Providers' Responses
    #{others_summary}

    ## Detected Disagreements
    #{disagreements_summary}

    ## Task
    Review the other responses and disagreements. Revise your answer and confidence if warranted.

    Respond with ONLY valid JSON matching the same schema. You may:
    - Keep your answer if you believe it's correct
    - Revise your answer based on valid points from others
    - Adjust your confidence based on agreement/disagreement

    Do NOT simply agree with the majority. Maintain your position if you believe you're correct.

    {
      "answer": "Your complete answer as a string",
      "confidence": <number 0.0 to 1.0 representing your confidence>,
      "key_claims": ["list", "of", "main", "factual", "claims"],
      "assumptions": ["list", "of", "assumptions", "you", "made"],
      "citations": [{"title": "Source name or null", "url": "URL or null"}]
    }
    """
  end

  @doc """
  Generate the dredd prompt for synthesizing final answer.
  """
  def dredd(question, responses, num_rounds) do
    formatted_responses = format_responses_for_dredd(responses)

    """
    You are the Dredd (arbiter) in a multi-model consensus process. Multiple AI models have answered a question across #{num_rounds} rounds. Your task is to synthesize a final answer.

    IMPORTANT: Your final_answer MUST be in the SAME LANGUAGE as the question below.

    Question: #{question}

    Model Responses (final round):
    #{formatted_responses}

    Analyze the responses and produce ONLY valid JSON matching this exact schema:
    {
      "final_answer": "The synthesized, accurate answer",
      "agreements": ["Points all or most models agree on"],
      "conflicts": [
        {
          "topic": "Brief topic description",
          "claims": [
            {"provider": "provider_name", "claim": "Their position"}
          ],
          "resolution": "Your resolution of this conflict with reasoning",
          "status": "RESOLVED or UNRESOLVED",
          "confidence": <0.0-1.0 confidence in your resolution>
        }
      ],
      "fact_table": [
        {"claim": "A factual claim", "support": ["provider1", "provider2"], "confidence": 0.9}
      ],
      "next_questions": ["Follow-up questions that could clarify uncertainties"],
      "overall_confidence": <0.0-1.0>,
      "dredd_failed": false
    }

    Guidelines:
    - Prefer claims with more model support and higher confidence
    - Mark conflicts UNRESOLVED if you cannot determine which is correct
    - overall_confidence reflects confidence in final_answer, not just agreement level
    """
  end

  # Helper functions

  defp format_other_responses(responses) do
    responses
    |> Enum.map(fn {provider, model, response} ->
      answer = truncate_answer(response[:answer], 1500)
      """
      ### #{provider} (#{model}) - Confidence: #{response[:confidence] || "N/A"}
      Answer: #{answer}

      Key Claims:
      #{format_claims(response[:key_claims])}
      """
    end)
    |> Enum.join("\n")
  end

  defp truncate_answer(nil, _max_len), do: "No answer provided"
  defp truncate_answer(answer, max_len) when byte_size(answer) <= max_len, do: answer
  defp truncate_answer(answer, max_len), do: String.slice(answer, 0, max_len) <> "..."

  defp format_claims(nil), do: "- None provided"

  defp format_claims(claims) when is_list(claims) do
    claims
    |> Enum.map(&"- #{&1}")
    |> Enum.join("\n")
  end

  defp format_claims(_), do: "- None provided"

  defp format_disagreements([]), do: "No significant disagreements detected."

  defp format_disagreements(disagreements) do
    disagreements
    |> Enum.map(fn {topic, positions} ->
      position_text =
        positions
        |> Enum.map(fn {provider, claim} -> "#{provider} claims \"#{claim}\"" end)
        |> Enum.join(", ")

      "- #{topic}: #{position_text}"
    end)
    |> Enum.join("\n")
  end

  defp format_responses_for_dredd(responses) do
    responses
    |> Enum.map(fn {provider, model, response} ->
      """
      ### #{provider} (#{model})
      Confidence: #{response[:confidence] || "N/A"}
      Answer: #{response[:answer] || "No answer provided"}
      Key Claims: #{format_claims(response[:key_claims])}
      """
    end)
    |> Enum.join("\n---\n")
  end
end
