defmodule Watchman.Repo.Migrations.AddCategoryToNewsItems do
  use Ecto.Migration

  def change do
    alter table(:news_items) do
      add :category, :string, null: false, default: "other"
    end

    execute(
      "UPDATE news_items SET source = 'unknown' WHERE source IS NULL",
      "UPDATE news_items SET source = NULL WHERE source = 'unknown'"
    )

    create index(:news_items, [:source])
    create index(:news_items, [:category])
  end
end
