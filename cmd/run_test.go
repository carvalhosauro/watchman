package cmd

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func TestRunCommand(t *testing.T) {
	orig := prices.BaseURL
	t.Cleanup(func() { prices.BaseURL = orig })
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"chart":{"error":null,"result":[{"timestamp":[1,2,3,4],"indicators":{"quote":[{"close":[10,10,10,11],"volume":[1,1,1,1]}]}}]}}`))
	}))
	defer srv.Close()
	prices.BaseURL = srv.URL

	wf := filepath.Join(t.TempDir(), "wallet")
	if err := os.WriteFile(wf, []byte("PETR4\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("WATCHMAN_WALLET", wf)
	t.Setenv("WATCHMAN_CONFIG", filepath.Join(t.TempDir(), "none.toml")) // hermetic: force defaults

	var out bytes.Buffer
	rootCmd.SetOut(&out)
	rootCmd.SetArgs([]string{"run"})
	if err := rootCmd.Execute(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "PETR4") {
		t.Fatalf("output missing PETR4:\n%s", out.String())
	}
}
