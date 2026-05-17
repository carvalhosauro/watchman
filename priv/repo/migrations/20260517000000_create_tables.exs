defmodule Watchman.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def change do
    create table(:assets) do
      add :ticker, :string, null: false
      add :name, :string
      add :type, :string
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:assets, [:ticker])

    create table(:price_snapshots) do
      add :asset_id, references(:assets, on_delete: :delete_all), null: false
      add :price, :float, null: false
      add :variation_day, :float
      add :variation_week, :float
      add :variation_month, :float
      add :fetched_at, :utc_datetime, default: fragment("CURRENT_TIMESTAMP")
    end

    create index(:price_snapshots, [:asset_id])

    create table(:news_items) do
      add :asset_id, references(:assets, on_delete: :delete_all), null: false
      add :title, :string
      add :summary, :text
      add :source, :string
      add :url, :string
      add :published_at, :utc_datetime
      add :fetched_at, :utc_datetime, default: fragment("CURRENT_TIMESTAMP")
    end

    create index(:news_items, [:asset_id])

    create table(:analyses) do
      add :asset_id, references(:assets, on_delete: :delete_all), null: false
      add :snapshot_id, references(:price_snapshots, on_delete: :nilify_all)
      add :cause, :text
      add :is_specific_problem, :boolean
      add :macro_context, :text
      add :recommendation, :string
      add :justification, :text
      add :tokens_used, :integer
      add :cost_usd, :float
      add :analyzed_at, :utc_datetime, default: fragment("CURRENT_TIMESTAMP")
    end

    create index(:analyses, [:asset_id])
    create index(:analyses, [:analyzed_at])

    create table(:retrospectives) do
      add :period_type, :string, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :content, :text
      add :generated_at, :utc_datetime, default: fragment("CURRENT_TIMESTAMP")
    end
  end
end
