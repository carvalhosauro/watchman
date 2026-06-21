package signals

import (
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func bars(closes ...float64) []prices.Bar {
	out := make([]prices.Bar, len(closes))
	for i, c := range closes {
		out[i] = prices.Bar{Close: c, Volume: 1000}
	}
	return out
}

func TestZScore(t *testing.T) {
	flat := make([]float64, 30)
	for i := range flat {
		flat[i] = 10
	}
	jump := append(append([]float64{}, flat...), 13) // +30% after flat
	s, ok := zscore(bars(jump...), Defaults())
	if !ok || s.Severity != Look {
		t.Fatalf("jump: got %+v ok=%v", s, ok)
	}

	calm := make([]float64, 40)
	for i := range calm {
		calm[i] = 10 + 0.01*float64(i%3)
	}
	if s, _ := zscore(bars(calm...), Defaults()); s.Severity != Calm {
		t.Fatalf("calm: got %+v", s)
	}

	if _, ok := zscore(bars(10), Defaults()); ok {
		t.Fatal("want ok=false for <3 closes")
	}
}
