defmodule Watchman.Repo.Migrations.AddAnalysisOutcomes do
  use Ecto.Migration

  def change do
    create table(:analysis_outcomes) do
      add :analysis_id, references(:analyses, on_delete: :delete_all), null: false
      add :lookahead_days, :integer, null: false
      add :baseline_price, :float, null: false
      add :observed_price, :float, null: false

      add :observed_snapshot_id,
          references(:price_snapshots, on_delete: :nilify_all),
          null: false

      add :variation_pct, :float, null: false
      add :outcome, :string, null: false
      add :drop_threshold_pct, :float, null: false
      add :evaluated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:analysis_outcomes, [:analysis_id])
    create index(:analysis_outcomes, [:outcome])
    create index(:analysis_outcomes, [:evaluated_at])
  end
end
