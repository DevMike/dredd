defmodule LlmMarket.Repo.Migrations.FixProviderAnswersArrayLength do
  use Ecto.Migration

  def change do
    # Change array element type from varchar(255) to text
    # to allow longer individual claims/assumptions
    alter table(:provider_answers) do
      modify :key_claims, {:array, :text}, from: {:array, :string}
      modify :assumptions, {:array, :text}, from: {:array, :string}
    end
  end
end
