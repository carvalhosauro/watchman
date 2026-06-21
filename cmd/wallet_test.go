package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWalletCommands(t *testing.T) {
	wf := filepath.Join(t.TempDir(), "wallet")
	t.Setenv("WATCHMAN_WALLET", wf)

	rootCmd.SetArgs([]string{"wallet", "add", "petr4"})
	if err := rootCmd.Execute(); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(wf); string(data) != "PETR4\n" {
		t.Fatalf("wallet file = %q", string(data))
	}
}
