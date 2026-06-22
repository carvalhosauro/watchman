package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

const volWindow = 20

// volume scores the latest volume against its trailing-window average.
func volume(bars []prices.Bar, t Thresholds) (Signal, bool) {
	if len(bars) < volWindow+1 {
		return Signal{}, false
	}
	window := bars[len(bars)-volWindow-1 : len(bars)-1]
	var sum float64
	for _, b := range window {
		sum += b.Volume
	}
	avg := sum / float64(volWindow)
	if avg == 0 {
		return Signal{}, false
	}
	ratio := bars[len(bars)-1].Volume / avg
	sev := Calm
	switch {
	case ratio >= t.VolLook:
		sev = Look
	case ratio >= t.VolWatch:
		sev = Watch
	}
	return Signal{Name: "volume", Value: ratio, Severity: sev,
		Reason: fmt.Sprintf("vol %.1f×", ratio)}, true
}
