package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/carvalhosauro/watchman/cmd"
	"github.com/rogpeppe/go-internal/testscript"
)

// TestMain lets testscript invoke the wm binary in-process: when a script runs
// `wm …`, the test binary re-execs itself and dispatches to cmd.Run.
func TestMain(m *testing.M) {
	os.Exit(testscript.RunMain(m, map[string]func() int{
		"wm": cmd.Run,
	}))
}

// TestScripts runs every .txtar under testdata/script as a black-box CLI flow,
// with the price/news upstreams pointed at a local mock and an isolated wallet.
func TestScripts(t *testing.T) {
	srv := newMockServer(t)
	testscript.Run(t, testscript.Params{
		Dir: "testdata/script",
		Setup: func(e *testscript.Env) error {
			e.Setenv("WATCHMAN_PRICES_URL", srv.URL+"/prices")
			e.Setenv("WATCHMAN_NEWS_URL", srv.URL+"/news")
			e.Setenv("WATCHMAN_WALLET", filepath.Join(e.WorkDir, "wallet"))
			return nil
		},
	})
}
