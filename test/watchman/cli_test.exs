defmodule Watchman.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Watchman.Models.Asset
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "assets command" do
    test "registers new asset with auto-detected type" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "XPTO3"])
        end)

      assert output =~ "+ XPTO3 (acao)"
      assert Repo.get_by(Asset, ticker: "XPTO3")
    end

    test "auto-detects FII type for ticker ending in 11" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "ZZZZ11"])
        end)

      assert output =~ "+ ZZZZ11 (fii)"
      asset = Repo.get_by(Asset, ticker: "ZZZZ11")
      assert asset.type == "fii"
    end

    test "handles explicit type override" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "ABCD11:acao"])
        end)

      assert output =~ "+ ABCD11 (acao)"
      asset = Repo.get_by(Asset, ticker: "ABCD11")
      assert asset.type == "acao"
    end

    test "skips already tracked asset" do
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "DUPL3", type: "acao"}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "DUPL3"])
        end)

      assert output =~ "~ DUPL3 (already tracked)"
    end

    test "upcases ticker input" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "lowcase3"])
        end)

      assert output =~ "+ LOWCASE3"
    end

    test "reactivates removed asset" do
      {:ok, asset} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "GONE3", type: "acao"}))
      Repo.update!(Asset.changeset(asset, %{active: false}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "GONE3"])
        end)

      assert output =~ "+ GONE3 (reactivated"
      assert Repo.get_by(Asset, ticker: "GONE3").active == true
    end
  end

  describe "list command" do
    test "shows tracked assets" do
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "LST13", type: "acao"}))
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "LST211", type: "fii"}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["list"])
        end)

      assert output =~ "LST13 (acao)"
      assert output =~ "LST211 (fii)"
    end

    test "shows message when no assets tracked" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["list"])
        end)

      assert output =~ "No assets tracked"
    end
  end

  describe "remove command" do
    test "deactivates asset" do
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "RMVX3", type: "acao"}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["remove", "RMVX3"])
        end)

      assert output =~ "- RMVX3"
      assert Repo.get_by(Asset, ticker: "RMVX3").active == false
    end

    test "reports not found" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["remove", "GHOST9"])
        end)

      assert output =~ "? GHOST9 (not found)"
    end
  end

  describe "usage" do
    test "shows usage on no args" do
      output =
        capture_io(fn ->
          Watchman.CLI.main([])
        end)

      assert output =~ "watchman - financial asset monitor"
      assert output =~ "wm setup"
    end
  end
end
