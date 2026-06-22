// Package config loads tunable signal thresholds from a TOML file, falling
// back to signals.Defaults() for any missing value.
package config

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
	"github.com/carvalhosauro/watchman/internal/signals"
)

// Path is the config file location; WATCHMAN_CONFIG overrides it.
func Path() string {
	if p := os.Getenv("WATCHMAN_CONFIG"); p != "" {
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "watchman", "config.toml")
}

// file mirrors the TOML layout; pointers tell "absent" from "zero".
type file struct {
	Zscore   struct{ Watch, Look *float64 }
	RSI      struct{ WatchHigh, LookHigh, WatchLow, LookLow *float64 } `toml:"rsi"`
	Drawdown struct{ Watch, Look *float64 }
	Prox52w  struct{ Band *float64 } `toml:"prox52w"`
	Volume   struct{ Watch, Look *float64 }
}

// Load reads the config file and fills missing keys from defaults.
func Load() (signals.Thresholds, error) {
	t := signals.Defaults()
	var f file
	if _, err := toml.DecodeFile(Path(), &f); err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return t, nil // no file → all defaults
		}
		return t, err
	}
	set := func(dst *float64, src *float64) {
		if src != nil {
			*dst = *src
		}
	}
	set(&t.ZWatch, f.Zscore.Watch)
	set(&t.ZLook, f.Zscore.Look)
	set(&t.RSIWatchHigh, f.RSI.WatchHigh)
	set(&t.RSILookHigh, f.RSI.LookHigh)
	set(&t.RSIWatchLow, f.RSI.WatchLow)
	set(&t.RSILookLow, f.RSI.LookLow)
	set(&t.DrawWatch, f.Drawdown.Watch)
	set(&t.DrawLook, f.Drawdown.Look)
	set(&t.Prox52Band, f.Prox52w.Band)
	set(&t.VolWatch, f.Volume.Watch)
	set(&t.VolLook, f.Volume.Look)
	return t, nil
}
