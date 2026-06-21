package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

// drawdown is the percent decline of the latest close from the trailing peak.
func drawdown(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < 2 {
		return Signal{}, false
	}
	peak := cs[0]
	for _, c := range cs {
		if c > peak {
			peak = c
		}
	}
	dd := 0.0
	if peak != 0 {
		dd = (cs[len(cs)-1] - peak) / peak * 100
	}
	sev := Calm
	switch {
	case dd <= t.DrawLook:
		sev = Look
	case dd <= t.DrawWatch:
		sev = Watch
	}
	return Signal{Name: "drawdown", Value: dd, Severity: sev,
		Reason: fmt.Sprintf("%.0f%% vs peak", dd)}, true
}
