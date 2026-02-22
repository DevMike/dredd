defmodule LlmMarket.Schemas.Thread do
  @moduledoc """
  Represents a Telegram chat thread with its settings.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "threads" do
    field :telegram_chat_id, :integer
    field :default_dredd_provider, :string
    field :default_dredd_model, :string
    field :settings, :map, default: %{}

    has_many :runs, LlmMarket.Schemas.Run

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a thread.
  """
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:telegram_chat_id, :default_dredd_provider, :default_dredd_model, :settings])
    |> validate_required([:telegram_chat_id])
    |> unique_constraint(:telegram_chat_id)
  end

  @doc """
  Get the dredd configuration for this thread.
  Falls back to application defaults if not set.
  """
  def get_dredd(%__MODULE__{} = thread) do
    if thread.default_dredd_provider && thread.default_dredd_model do
      {String.to_atom(thread.default_dredd_provider), thread.default_dredd_model}
    else
      LlmMarket.dredd_config()[:default]
    end
  end
end
