// Package signals computes deterministic price/volume anomaly signals. Each
// signal is a pure function over a bar series; severity is the signal's own
// judgement against tunable thresholds.
package signals

import "math"

// Severity ranks how much attention a signal demands.
type Severity int

const (
	Calm Severity = iota
	Watch
	Look
)

func (s Severity) String() string {
	switch s {
	case Look:
		return "LOOK"
	case Watch:
		return "watch"
	default:
		return "calm"
	}
}

// Signal is one indicator's reading for a ticker.
type Signal struct {
	Name     string
	Value    float64
	Severity Severity
	Reason   string
}

// Thresholds are the tunable cutoffs for every signal.
type Thresholds struct {
	ZWatch, ZLook                                      float64
	RSIWatchHigh, RSILookHigh, RSIWatchLow, RSILookLow float64
	DrawWatch, DrawLook                                float64 // percent, negative
	Prox52Band                                         float64 // percent
	VolWatch, VolLook                                  float64 // ×avg
}

// Defaults are the built-in thresholds used when config omits a value.
func Defaults() Thresholds {
	return Thresholds{
		ZWatch: 2, ZLook: 3,
		RSIWatchHigh: 70, RSILookHigh: 80, RSIWatchLow: 30, RSILookLow: 20,
		DrawWatch: -10, DrawLook: -20,
		Prox52Band: 3,
		VolWatch: 2, VolLook: 3,
	}
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
