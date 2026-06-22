package signals

import (
	"fmt"
	"math"

	"github.com/carvalhosauro/watchman/internal/prices"
)

// closeSeries extracts closes oldest→newest.
func closeSeries(bars []prices.Bar) []float64 {
	out := make([]float64, len(bars))
	for i, b := range bars {
		out[i] = b.Close
	}
	return out
}

// zscore scores how unusual the latest daily return is vs the prior returns.
func zscore(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < 3 {
		return Signal{}, false
	}
	returns := make([]float64, 0, len(cs)-1)
	for i := 1; i < len(cs); i++ {
		returns = append(returns, (cs[i]-cs[i-1])/cs[i-1]*100)
	}
	latest := returns[len(returns)-1]
	prior := returns[:len(returns)-1]
	mu := mean(prior)
	sigma := stddev(prior, mu)
	z := 0.0
	switch {
	case sigma != 0:
		z = (latest - mu) / sigma
	case latest != mu:
		z = math.Copysign(math.Inf(1), latest-mu)
	}
	sev := Calm
	switch {
	case math.Abs(z) >= t.ZLook:
		sev = Look
	case math.Abs(z) >= t.ZWatch:
		sev = Watch
	}
	return Signal{Name: "zscore", Value: z, Severity: sev,
		Reason: fmt.Sprintf("%.1f%% (%.1fσ)", latest, z)}, true
}
