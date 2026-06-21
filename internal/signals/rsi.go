package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

const rsiPeriod = 14

// rsi is the Wilder Relative Strength Index over the last rsiPeriod deltas.
func rsi(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < rsiPeriod+1 {
		return Signal{}, false
	}
	var gain, loss float64
	for i := 1; i <= rsiPeriod; i++ {
		d := cs[i] - cs[i-1]
		if d >= 0 {
			gain += d
		} else {
			loss -= d
		}
	}
	avgGain, avgLoss := gain/rsiPeriod, loss/rsiPeriod
	for i := rsiPeriod + 1; i < len(cs); i++ {
		d := cs[i] - cs[i-1]
		g, l := 0.0, 0.0
		if d >= 0 {
			g = d
		} else {
			l = -d
		}
		avgGain = (avgGain*(rsiPeriod-1) + g) / rsiPeriod
		avgLoss = (avgLoss*(rsiPeriod-1) + l) / rsiPeriod
	}
	r := 100.0
	if avgLoss != 0 {
		r = 100 - 100/(1+avgGain/avgLoss)
	}
	sev := Calm
	switch {
	case r >= t.RSILookHigh || r <= t.RSILookLow:
		sev = Look
	case r >= t.RSIWatchHigh || r <= t.RSIWatchLow:
		sev = Watch
	}
	return Signal{Name: "rsi", Value: r, Severity: sev,
		Reason: fmt.Sprintf("RSI %.0f", r)}, true
}
