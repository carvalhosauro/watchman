package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGenerate(t *testing.T) {
	dir := t.TempDir()
	if err := generate(dir); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{
		"completions/wm.bash",
		"completions/wm.zsh",
		"completions/wm.fish",
		"manpages/wm.1",
		"manpages/wm-wallet.1",
		"manpages/wm-run.1",
	} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Errorf("expected %s: %v", f, err)
		}
	}
}
