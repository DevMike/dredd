defmodule LlmMarket.Schemas.DreddOutput do
  @moduledoc """
  Represents the Dredd's (arbiter) synthesized output for a run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dredd_outputs" do
    field :dredd_provider, :string
    field :dredd_model, :string
    field :final_answer, :string
    field :agreements, {:array, :string}
    field :conflicts, :map
    field :fact_table, :map
    field :next_questions, {:array, :string}
    field :overall_confidence, :decimal
    field :dredd_failed, :boolean, default: false
    field :latency_ms, :integer
    field :cost_usd, :decimal

    belongs_to :run, LlmMarket.Schemas.Run

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a dredd output.
  """
  def changeset(output, attrs) do
    output
    |> cast(attrs, [
      :run_id,
      :dredd_provider,
      :dredd_model,
      :final_answer,
      :agreements,
      :conflicts,
      :fact_table,
      :next_questions,
      :overall_confidence,
      :dredd_failed,
      :latency_ms,
      :cost_usd
    ])
    |> validate_required([:run_id, :dredd_provider, :dredd_model])
    |> validate_number(:overall_confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint(:run_id)
    |> foreign_key_constraint(:run_id)
  end

  @doc """
  Create a dredd output from a parsed response.
  """
  def from_parsed(run_id, provider, model, parsed, latency_ms, cost_usd) do
    %{
      run_id: run_id,
      dredd_provider: to_string(provider),
      dredd_model: model,
      final_answer: parsed["final_answer"],
      agreements: parsed["agreements"],
      conflicts: normalize_conflicts(parsed["conflicts"]),
      fact_table: normalize_fact_table(parsed["fact_table"]),
      next_questions: parsed["next_questions"],
      overall_confidence: parsed["overall_confidence"],
      dredd_failed: parsed["dredd_failed"] || false,
      latency_ms: latency_ms,
      cost_usd: cost_usd
    }
  end

  @doc """
  Create a failed dredd output.
  """
  def failed(run_id, provider, model, latency_ms) do
    %{
      run_id: run_id,
      dredd_provider: to_string(provider),
      dredd_model: model,
      final_answer: nil,
      dredd_failed: true,
      latency_ms: latency_ms
    }
  end

  defp normalize_conflicts(nil), do: nil
  defp normalize_conflicts(conflicts) when is_list(conflicts), do: %{items: conflicts}
  defp normalize_conflicts(conflicts) when is_map(conflicts), do: conflicts

  defp normalize_fact_table(nil), do: nil
  defp normalize_fact_table(table) when is_list(table), do: %{items: table}
  defp normalize_fact_table(table) when is_map(table), do: table
end
