defmodule LlmMarket.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :question, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :rounds_completed, :integer, default: 0
      add :convergence_achieved, :boolean, default: false
      add :total_latency_ms, :integer
      add :total_cost_usd, :decimal, precision: 10, scale: 6

      timestamps(type: :utc_datetime)
    end

    create index(:runs, [:thread_id])
    create index(:runs, [:inserted_at])
    create index(:runs, [:status])
  end
end
