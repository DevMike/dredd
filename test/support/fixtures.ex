defmodule LlmMarket.Test.Fixtures do
  @moduledoc """
  Test fixtures for LLM Market tests.
  """

  def valid_provider_response do
    %{
      "answer" => "The answer is 42.",
      "confidence" => 0.85,
      "key_claims" => ["claim 1", "claim 2"],
      "assumptions" => ["assumption 1"],
      "citations" => []
    }
  end

  def openai_raw_response do
    %{
      "id" => "chatcmpl-123",
      "object" => "chat.completion",
      "created" => 1_677_652_288,
      "model" => "gpt-4o",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => Jason.encode!(valid_provider_response())
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
    }
  end

  def anthropic_raw_response do
    %{
      "id" => "msg_123",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-sonnet-4-20250514",
      "content" => [
        %{
          "type" => "text",
          "text" => Jason.encode!(valid_provider_response())
        }
      ],
      "stop_reason" => "end_turn",
      "usage" => %{
        "input_tokens" => 100,
        "output_tokens" => 50
      }
    }
  end

  def judge_response do
    %{
      "final_answer" => "The synthesized answer is 42.",
      "agreements" => ["All models agree on 42"],
      "conflicts" => [],
      "fact_table" => [
        %{"claim" => "The answer is 42", "support" => ["openai", "anthropic"], "confidence" => 0.9}
      ],
      "next_questions" => [],
      "overall_confidence" => 0.9,
      "judge_failed" => false
    }
  end

  def thread_attrs do
    %{
      telegram_chat_id: 123_456_789
    }
  end

  def run_attrs(thread_id) do
    %{
      thread_id: thread_id,
      question: "What is the meaning of life?",
      status: "pending"
    }
  end

  def provider_answer_attrs(run_id) do
    %{
      run_id: run_id,
      round: 1,
      provider: "openai",
      model: "gpt-4o",
      status: "ok",
      answer: "The answer is 42.",
      confidence: Decimal.new("0.85"),
      key_claims: ["claim 1", "claim 2"],
      assumptions: ["assumption 1"],
      latency_ms: 1500
    }
  end
end
