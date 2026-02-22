defmodule LlmMarket.Schemas.Run do
  @moduledoc """
  Represents a single question-answer run through the market.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending in_progress completed failed cancelled)

  schema "runs" do
    field :question, :string
    field :status, :string, default: "pending"
    field :rounds_completed, :integer, default: 0
    field :convergence_achieved, :boolean, default: false
    field :total_latency_ms, :integer
    field :total_cost_usd, :decimal

    belongs_to :thread, LlmMarket.Schemas.Thread
    has_many :provider_answers, LlmMarket.Schemas.ProviderAnswer
    has_one :dredd_output, LlmMarket.Schemas.DreddOutput

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new run.
  """
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :question,
      :status,
      :rounds_completed,
      :convergence_achieved,
      :total_latency_ms,
      :total_cost_usd,
      :thread_id
    ])
    |> validate_required([:question, :thread_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:thread_id)
  end

  @doc """
  Update run status.
  """
  def status_changeset(run, status) do
    run
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Update run after round completion.
  """
  def round_complete_changeset(run, attrs) do
    run
    |> cast(attrs, [:rounds_completed, :convergence_achieved])
  end

  @doc """
  Update run completion metrics.
  """
  def complete_changeset(run, attrs) do
    run
    |> cast(attrs, [:status, :rounds_completed, :convergence_achieved, :total_latency_ms, :total_cost_usd])
    |> validate_inclusion(:status, @statuses)
  end
end
