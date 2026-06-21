package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

const prox52Min = 200

// prox52w scores how close the latest close is to its 1-year high/low.
func prox52w(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < prox52Min {
		return Signal{}, false
	}
	hi, lo := cs[0], cs[0]
	for _, c := range cs {
		if c > hi {
			hi = c
		}
		if c < lo {
			lo = c
		}
	}
	last := cs[len(cs)-1]
	toHigh, toLow := 100.0, 100.0
	if hi != 0 {
		toHigh = (hi - last) / hi * 100
	}
	if lo != 0 {
		toLow = (last - lo) / lo * 100
	}
	near := toHigh
	label := "to 52w high"
	if toLow < toHigh {
		near, label = toLow, "to 52w low"
	}
	sev := Calm
	switch {
	case last >= hi || last <= lo:
		sev = Look
	case near <= t.Prox52Band:
		sev = Watch
	}
	return Signal{Name: "prox52w", Value: near, Severity: sev,
		Reason: fmt.Sprintf("%.1f%% %s", near, label)}, true
}
