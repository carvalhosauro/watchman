defmodule Watchman.Models.Retrospective do
  use Ecto.Schema
  import Ecto.Changeset

  schema "retrospectives" do
    field :period_type, :string
    field :start_date, :date
    field :end_date, :date
    field :content, :string
    field :generated_at, :utc_datetime
  end

  def changeset(retrospective, attrs) do
    retrospective
    |> cast(attrs, [:period_type, :start_date, :end_date, :content, :generated_at])
    |> validate_required([:period_type, :start_date, :end_date])
    |> validate_inclusion(:period_type, ~w(weekly monthly))
  end
end
