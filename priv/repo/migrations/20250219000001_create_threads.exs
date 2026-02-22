defmodule LlmMarket.Repo.Migrations.CreateThreads do
  use Ecto.Migration

  def change do
    create table(:threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :telegram_chat_id, :bigint, null: false
      add :default_dredd_provider, :string
      add :default_dredd_model, :string
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:threads, [:telegram_chat_id])
  end
end
