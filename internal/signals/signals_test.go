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

func volBars(vols ...float64) []prices.Bar {
	out := make([]prices.Bar, len(vols))
	for i, v := range vols {
		out[i] = prices.Bar{Close: 10, Volume: v}
	}
	return out
}

func TestRSI(t *testing.T) {
	up := make([]float64, 20) // monotonic rise → RSI ~100 → Look
	for i := range up {
		up[i] = 10 + float64(i)
	}
	if s, ok := rsi(bars(up...), Defaults()); !ok || s.Severity != Look || s.Value <= 80 {
		t.Fatalf("up: got %+v ok=%v", s, ok)
	}
	if _, ok := rsi(bars(10, 11), Defaults()); ok {
		t.Fatal("want ok=false for <15 closes")
	}
}

func TestDrawdown(t *testing.T) {
	if s, ok := drawdown(bars(10, 20, 18, 15), Defaults()); !ok || s.Severity != Look {
		t.Fatalf("deep: got %+v ok=%v", s, ok)
	}
	if s, _ := drawdown(bars(10, 11, 12), Defaults()); s.Severity != Calm {
		t.Fatalf("rising: got %+v", s)
	}
}

func TestProx52w(t *testing.T) {
	hi := make([]float64, 200)
	for i := range hi {
		hi[i] = 10 + float64(i)*0.1 // ends at the high → Look (new high)
	}
	if r, ok := prox52w(bars(hi...), Defaults()); !ok || r.Severity != Look {
		t.Fatalf("high: got %+v ok=%v", r, ok)
	}
	mid := make([]float64, 200)
	for i := range mid {
		mid[i] = 10 + float64(i)*0.1
	}
	mid[len(mid)-1] = 20 // far from the 29.9 high and the 10 low
	if r, _ := prox52w(bars(mid...), Defaults()); r.Severity != Calm {
		t.Fatalf("mid: got %+v", r)
	}
	if _, ok := prox52w(bars(10, 11), Defaults()); ok {
		t.Fatal("want ok=false for <200 closes")
	}
}

func TestVolume(t *testing.T) {
	v := make([]float64, 21)
	for i := range v {
		v[i] = 100
	}
	v[len(v)-1] = 400 // 4× the 100-avg → Look
	if s, ok := volume(volBars(v...), Defaults()); !ok || s.Severity != Look {
		t.Fatalf("spike: got %+v ok=%v", s, ok)
	}
	if _, ok := volume(volBars(100, 100), Defaults()); ok {
		t.Fatal("want ok=false for <21 bars")
	}
}

func TestEvaluate(t *testing.T) {
	flat := make([]float64, 30)
	for i := range flat {
		flat[i] = 10
	}
	jump := append(append([]float64{}, flat...), 13)
	got := Evaluate(bars(jump...), Defaults())
	if len(got) == 0 {
		t.Fatal("Evaluate returned nothing")
	}
	var hasZ bool
	for _, s := range got {
		if s.Name == "zscore" {
			hasZ = true
		}
	}
	if !hasZ {
		t.Fatalf("zscore missing: %+v", got)
	}
}
