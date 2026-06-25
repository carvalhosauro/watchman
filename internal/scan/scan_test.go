package scan

import (
	"testing"
	"time"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func testBars(closes ...float64) []prices.Bar {
	out := make([]prices.Bar, len(closes))
	for i, c := range closes {
		out[i] = prices.Bar{Date: "2026-01-01", Close: c, Volume: 1000}
	}
	return out
}

func barsWithDates(closes []float64, startDate string) []prices.Bar {
	t, _ := time.Parse("2006-01-02", startDate)
	out := make([]prices.Bar, len(closes))
	for i, c := range closes {
		out[i] = prices.Bar{Date: t.Format("2006-01-02"), Close: c, Volume: 1000}
		t = t.AddDate(0, 0, 1)
	}
	return out
}

func TestCloseSeries(t *testing.T) {
	got := closeSeries(testBars(10, 20, 30))
	if len(got) != 3 || got[2] != 30 {
		t.Fatalf("got %v", got)
	}
}
