package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDefaultsWhenMissing(t *testing.T) {
	t.Setenv("WATCHMAN_CONFIG", filepath.Join(t.TempDir(), "nope.toml"))
	th, err := Load()
	if err != nil || th.ZLook != 3 || th.VolWatch != 2 {
		t.Fatalf("defaults not applied: %+v err=%v", th, err)
	}
}

func TestLoadOverride(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(p, []byte("[zscore]\nlook = 4.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("WATCHMAN_CONFIG", p)
	th, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if th.ZLook != 4.0 {
		t.Fatalf("override ZLook=%v", th.ZLook)
	}
	if th.ZWatch != 2.0 { // untouched key keeps default
		t.Fatalf("default ZWatch lost: %v", th.ZWatch)
	}
}
