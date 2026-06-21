package cmd

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/news"
	"github.com/carvalhosauro/watchman/internal/prices"
)

func TestRunCommand(t *testing.T) {
	origPrices, origFeed := prices.BaseURL, news.FeedURL
	t.Cleanup(func() { prices.BaseURL, news.FeedURL = origPrices, origFeed })

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`{"chart":{"error":null,"result":[{"indicators":{"quote":[{"close":[10,10,10,11]}]}}]}}`))
	}))
	defer srv.Close()
	prices.BaseURL = srv.URL
	// hermetic + fast: a closed server refuses at once → no real CVM call
	dead := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	dead.Close()
	news.FeedURL = dead.URL

	wf := filepath.Join(t.TempDir(), "wallet")
	os.WriteFile(wf, []byte("PETR4\n"), 0o644)
	t.Setenv("WATCHMAN_WALLET", wf)

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
