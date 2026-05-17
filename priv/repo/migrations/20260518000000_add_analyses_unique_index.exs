defmodule Watchman.Repo.Migrations.AddAnalysesUniqueIndex do
  use Ecto.Migration

  def change do
    create unique_index(:analyses, [:asset_id, :snapshot_id])
  end
end
