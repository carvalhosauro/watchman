// Package anomaly scores how unusual the latest daily move is vs recent returns.
package anomaly

import (
	"errors"
	"math"
)

const threshold = 2.0

// ErrInsufficient signals there are too few closes to compute a z-score.
var ErrInsufficient = errors.New("insufficient data")

// Result is the latest move expressed as a percent return and its z-score
// against the prior return distribution; Abnormal is |Z| >= threshold.
type Result struct {
	Pct      float64
	Z        float64
	Abnormal bool
}

// Analyze turns a close series (oldest→newest) into the latest-move z-score.
func Analyze(closes []float64) (Result, error) {
	if len(closes) < 3 {
		return Result{}, ErrInsufficient
	}
	returns := make([]float64, 0, len(closes)-1)
	for i := 1; i < len(closes); i++ {
		returns = append(returns, (closes[i]-closes[i-1])/closes[i-1]*100.0)
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
		// Zero historical variance but a real move today: infinitely surprising.
		z = math.Copysign(math.Inf(1), latest-mu)
	}
	return Result{Pct: latest, Z: z, Abnormal: math.Abs(z) >= threshold}, nil
}

func mean(xs []float64) float64 {
	s := 0.0
	for _, x := range xs {
		s += x
	}
	return s / float64(len(xs))
}

func stddev(xs []float64, mu float64) float64 {
	s := 0.0
	for _, x := range xs {
		s += (x - mu) * (x - mu)
	}
	return math.Sqrt(s / float64(len(xs)))
}
