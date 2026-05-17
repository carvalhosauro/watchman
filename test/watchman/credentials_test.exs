defmodule Watchman.CredentialsTest do
  use ExUnit.Case

  describe "available?/0" do
    test "returns a boolean" do
      result = Watchman.Credentials.available?()
      assert is_boolean(result)
    end
  end

  describe "get/1" do
    test "returns nil for non-existent string key" do
      assert Watchman.Credentials.get("watchman_test_nonexistent_key_xyz") == nil
    end

    test "returns nil for non-existent atom key" do
      assert Watchman.Credentials.get(:watchman_test_nonexistent_atom_key) == nil
    end
  end
end
