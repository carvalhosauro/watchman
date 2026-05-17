defmodule Watchman.Models.RetrospectiveTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.Retrospective
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "changeset/2" do
    test "valid changeset with period_type, start_date, and end_date" do
      changeset =
        Retrospective.changeset(%Retrospective{}, %{
          period_type: "weekly",
          start_date: ~D[2026-01-01],
          end_date: ~D[2026-01-07]
        })

      assert changeset.valid?
    end

    test "validates period_type - weekly is valid" do
      changeset =
        Retrospective.changeset(%Retrospective{}, %{
          period_type: "weekly",
          start_date: ~D[2026-01-01],
          end_date: ~D[2026-01-07]
        })

      assert changeset.valid?
    end

    test "validates period_type - monthly is valid" do
      changeset =
        Retrospective.changeset(%Retrospective{}, %{
          period_type: "monthly",
          start_date: ~D[2026-01-01],
          end_date: ~D[2026-01-31]
        })

      assert changeset.valid?
    end

    test "rejects invalid period_type" do
      changeset =
        Retrospective.changeset(%Retrospective{}, %{
          period_type: "daily",
          start_date: ~D[2026-01-01],
          end_date: ~D[2026-01-01]
        })

      refute changeset.valid?
      assert {:period_type, {"is invalid", [validation: :inclusion, enum: ["weekly", "monthly"]]}} in changeset.errors
    end

    test "requires start_date" do
      changeset =
        Retrospective.changeset(%Retrospective{}, %{
          period_type: "weekly",
          end_date: ~D[2026-01-07]
        })

      refute changeset.valid?
      assert {:start_date, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires end_date" do
      changeset =
        Retrospective.changeset(%Retrospective{}, %{
          period_type: "weekly",
          start_date: ~D[2026-01-01]
        })

      refute changeset.valid?
      assert {:end_date, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires period_type" do
      changeset =
        Retrospective.changeset(%Retrospective{}, %{
          start_date: ~D[2026-01-01],
          end_date: ~D[2026-01-07]
        })

      refute changeset.valid?
      assert {:period_type, {"can't be blank", [validation: :required]}} in changeset.errors
    end
  end
end
