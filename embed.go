// Package watchman bundles assets compiled into the wm binary — currently the
// indicator reference docs surfaced by `wm explain`. The markdown lives under
// docs/indicators/ (human-readable, single source of truth) and is embedded
// here because //go:embed cannot reach files outside the embedding package's
// directory, and the module root is the only Go-package ancestor of docs/.
package watchman

import (
	"embed"
	"fmt"
)

//go:embed docs/indicators/range.md docs/indicators/drawdown.md docs/indicators/sma200.md docs/indicators/rsi.md docs/indicators/volume.md
var indicatorDocs embed.FS

// IndicatorKeys is the canonical display order for `wm explain --list` and the
// scan table columns.
var IndicatorKeys = []string{"range", "drawdown", "sma200", "rsi", "volume"}

// IndicatorDoc returns the reference markdown for key, or an error if key is not
// a known indicator.
func IndicatorDoc(key string) (string, error) {
	for _, k := range IndicatorKeys {
		if k == key {
			b, err := indicatorDocs.ReadFile("docs/indicators/" + key + ".md")
			if err != nil {
				return "", err
			}
			return string(b), nil
		}
	}
	return "", fmt.Errorf("unknown indicator %q", key)
}
