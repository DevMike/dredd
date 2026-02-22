defmodule LlmMarket.Repo.Migrations.CreateProviderAnswers do
  use Ecto.Migration

  def change do
    create table(:provider_answers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false
      add :round, :integer, null: false
      add :provider, :string, null: false
      add :model, :string
      add :status, :string, null: false, default: "ok"
      add :answer, :text
      add :confidence, :decimal, precision: 4, scale: 3
      add :key_claims, {:array, :string}
      add :assumptions, {:array, :string}
      add :citations, :map
      add :usage, :map
      add :latency_ms, :integer
      add :error, :map
      add :raw_response, :text

      timestamps(type: :utc_datetime)
    end

    create index(:provider_answers, [:run_id])
    create index(:provider_answers, [:run_id, :round])
    create index(:provider_answers, [:provider])
  end
end
