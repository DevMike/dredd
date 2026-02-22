defmodule LlmMarket.Schemas.ProviderAnswer do
  @moduledoc """
  Represents a single provider's answer for a specific round.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(ok error timeout parse_error)
  @providers ~w(openai anthropic gemini)

  schema "provider_answers" do
    field :round, :integer
    field :provider, :string
    field :model, :string
    field :status, :string, default: "ok"
    field :answer, :string
    field :confidence, :decimal
    field :key_claims, {:array, :string}
    field :assumptions, {:array, :string}
    field :citations, :map
    field :usage, :map
    field :latency_ms, :integer
    field :error, :map
    field :raw_response, :string

    belongs_to :run, LlmMarket.Schemas.Run

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a provider answer.
  """
  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [
      :run_id,
      :round,
      :provider,
      :model,
      :status,
      :answer,
      :confidence,
      :key_claims,
      :assumptions,
      :citations,
      :usage,
      :latency_ms,
      :error,
      :raw_response
    ])
    |> validate_required([:run_id, :round, :provider, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:provider, @providers)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:run_id)
  end

  @doc """
  Create a provider answer from a normalized response.
  """
  def from_normalized(run_id, round, provider, normalized) do
    %{
      run_id: run_id,
      round: round,
      provider: to_string(provider),
      model: normalized[:model],
      status: normalized[:status] || "ok",
      answer: normalized[:answer],
      confidence: normalized[:confidence],
      key_claims: normalized[:key_claims],
      assumptions: normalized[:assumptions],
      citations: normalize_citations(normalized[:citations]),
      usage: normalized[:usage],
      latency_ms: normalized[:latency_ms],
      error: normalized[:error],
      raw_response: if(LlmMarket.debug_mode?(), do: normalized[:raw_response])
    }
  end

  defp normalize_citations(nil), do: nil
  defp normalize_citations(citations) when is_list(citations), do: %{items: citations}
  defp normalize_citations(citations) when is_map(citations), do: citations
end
