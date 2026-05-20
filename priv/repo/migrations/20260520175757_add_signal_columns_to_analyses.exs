defmodule Watchman.Repo.Migrations.AddSignalColumnsToAnalyses do
  use Ecto.Migration

  def change do
    alter table(:analyses) do
      add :signal_level, :string, null: false, default: "noise"
      add :signal_direction, :string, null: false, default: "neutral"
      add :signal_reasons, :text, null: false, default: "[]"
      add :signal_confidence, :float, null: false, default: 0.0
    end

    create index(:analyses, [:signal_level])
    create index(:analyses, [:signal_direction])
  end
end
