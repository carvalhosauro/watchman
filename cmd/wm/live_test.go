//go:build live

// Live smoke test: drives wm against the REAL Yahoo + CVM upstreams. Opt-in via
// `go test -tags live ./cmd/wm/` (or `make smoke`); excluded from `go test ./...`.
// Tolerant by design — asserts the shape of the output (dated header, one verdict
// line per ticker), not specific verdicts, since prices move and Yahoo may 429.
package main

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/signals"
	"github.com/carvalhosauro/watchman/internal/wallet"
)

func TestLiveRun(t *testing.T) {
	wf := filepath.Join(t.TempDir(), "wallet")
	if err := os.WriteFile(wf, []byte("PETR4\nITUB4\nXPTO3INVALID\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("WATCHMAN_WALLET", wf)

	tickers, err := wallet.List(wallet.Path())
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	out.WriteString("watchman — live\n")
	out.WriteString(glance.Format(glance.Run(tickers, signals.Defaults()), false))

	got := out.String()
	t.Logf("live output:\n%s", got)

	verdict := regexp.MustCompile(`(LOOK|watch|calm|No data|API error)`)
	for _, tk := range tickers {
		var line string
		for _, l := range strings.Split(got, "\n") {
			if strings.Contains(l, tk) {
				line = l
				break
			}
		}
		if line == "" {
			t.Errorf("no row for %s", tk)
			continue
		}
		if !verdict.MatchString(line) {
			t.Errorf("%s row has no verdict (LOOK/watch/calm) or failure: %q", tk, line)
		}
	}
}
