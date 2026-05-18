defmodule Watchman.Repo.Migrations.AddAnalysesAssetDateUniqueIndex do
  use Ecto.Migration

  def up do
    execute "CREATE UNIQUE INDEX IF NOT EXISTS analyses_asset_date ON analyses (asset_id, date(analyzed_at))"
  end

  def down do
    execute "DROP INDEX IF EXISTS analyses_asset_date"
  end
end
