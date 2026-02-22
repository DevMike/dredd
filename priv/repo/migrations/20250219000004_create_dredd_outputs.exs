defmodule LlmMarket.Repo.Migrations.CreateDreddOutputs do
  use Ecto.Migration

  def change do
    create table(:dredd_outputs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false
      add :dredd_provider, :string, null: false
      add :dredd_model, :string, null: false
      add :final_answer, :text
      add :agreements, {:array, :string}
      add :conflicts, :map
      add :fact_table, :map
      add :next_questions, {:array, :string}
      add :overall_confidence, :decimal, precision: 4, scale: 3
      add :dredd_failed, :boolean, default: false
      add :latency_ms, :integer
      add :cost_usd, :decimal, precision: 10, scale: 6

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dredd_outputs, [:run_id])
  end
end
