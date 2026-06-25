package scan

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
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

func TestRangePct(t *testing.T) {
	lo := make([]float64, 200)
	for i := range lo {
		lo[i] = 10
	}
	lo[199] = 20 // close at high → 100%
	if v, ok := rangePct(testBars(lo...)); !ok || v < 99 {
		t.Fatalf("at high: got %v ok=%v", v, ok)
	}

	hi := make([]float64, 200)
	for i := range hi {
		hi[i] = 10 + float64(i)*0.1
	}
	// close near low of series after being high earlier — craft explicit:
	b := testBars(10, 20, 10, 20)
	b = b[:0]
	vals := make([]float64, 200)
	for i := range vals {
		vals[i] = 100
	}
	vals[199] = 10 // at low
	if v, ok := rangePct(testBars(vals...)); !ok || v > 1 {
		t.Fatalf("at low: got %v ok=%v", v, ok)
	}

	if _, ok := rangePct(testBars(10, 11)); ok {
		t.Fatal("want ok=false for <200 bars")
	}
}

func TestDrawdownPct(t *testing.T) {
	b := testBars(10, 20, 18, 15)
	b[1].Date = "2026-03-14"
	dd, peakDate, peakClose, ok := drawdownPct(b)
	if !ok || dd > -10 || peakClose != 20 || peakDate != "2026-03-14" {
		t.Fatalf("got dd=%v peak=%v@%v ok=%v", dd, peakClose, peakDate, ok)
	}
	if _, _, _, ok := drawdownPct(testBars(10)); ok {
		t.Fatal("want ok=false for 1 bar")
	}
}

func TestSMA200Pct(t *testing.T) {
	vals := make([]float64, 200)
	for i := range vals {
		vals[i] = 100
	}
	vals[199] = 110 // +10% above SMA200 of 100s... SMA of 100..99,100 with last 110
	b := testBars(vals...)
	pct, sma, ok := sma200Pct(b)
	if !ok || sma == 0 {
		t.Fatalf("got pct=%v sma=%v ok=%v", pct, sma, ok)
	}
	if pct <= 0 {
		t.Fatalf("want positive pct above sma, got %v", pct)
	}
	if _, _, ok := sma200Pct(testBars(10, 11)); ok {
		t.Fatal("want ok=false for <200 bars")
	}
}

func TestRSIValue(t *testing.T) {
	up := make([]float64, 20)
	for i := range up {
		up[i] = 10 + float64(i)
	}
	v, ok := rsiValue(testBars(up...))
	if !ok || v <= 80 {
		t.Fatalf("monotonic up: got %v ok=%v", v, ok)
	}
	if _, ok := rsiValue(testBars(10, 11)); ok {
		t.Fatal("want ok=false for <15 bars")
	}
}

func volBars(vols ...float64) []prices.Bar {
	out := make([]prices.Bar, len(vols))
	for i, v := range vols {
		out[i] = prices.Bar{Close: 10, Volume: v}
	}
	return out
}

func TestVolumeRatio(t *testing.T) {
	vols := make([]float64, 21)
	for i := range vols {
		vols[i] = 1000
	}
	vols[20] = 3000
	r, ok := volumeRatio(volBars(vols...))
	if !ok || r < 2.9 {
		t.Fatalf("got %v ok=%v", r, ok)
	}
	if _, ok := volumeRatio(volBars(1000)); ok {
		t.Fatal("want ok=false for <21 bars")
	}
}

func TestEvaluate(t *testing.T) {
	vals := make([]float64, 210)
	for i := range vals {
		vals[i] = 100
	}
	vals[209] = 50
	b := testBars(vals...)
	r := Evaluate("TEST", b)
	if r.Ticker != "TEST" || r.Close != 50 {
		t.Fatalf("got %+v", r)
	}
	if r.Readings.RangePct == nil || r.Readings.DrawdownPct == nil {
		t.Fatalf("want range+drawdown, got %+v", r.Readings)
	}
}

func TestBuildRowNoData(t *testing.T) {
	r := BuildRow("X", nil, prices.ErrNoData)
	if r.Error != "No data" {
		t.Fatalf("got %+v", r)
	}
}

func TestBuildRowAPIError(t *testing.T) {
	r := BuildRow("X", nil, errors.New("http 500"))
	if r.Error != "API error" {
		t.Fatalf("got %+v", r)
	}
}

type quoteJSON struct {
	Close  []float64 `json:"close"`
	Volume []float64 `json:"volume"`
}

// buildChart builds a Yahoo chart payload for the given closes (volume = 1000 each).
func buildChart(closes []float64) []byte {
	ts := make([]int64, len(closes))
	vol := make([]float64, len(closes))
	for i := range closes {
		ts[i] = int64(i) * 86400
		vol[i] = 1000
	}
	var r struct {
		Chart struct {
			Error  any `json:"error"`
			Result []struct {
				Timestamp  []int64 `json:"timestamp"`
				Indicators struct {
					Quote []quoteJSON `json:"quote"`
				} `json:"indicators"`
			} `json:"result"`
		} `json:"chart"`
	}
	res := struct {
		Timestamp  []int64 `json:"timestamp"`
		Indicators struct {
			Quote []quoteJSON `json:"quote"`
		} `json:"indicators"`
	}{Timestamp: ts}
	res.Indicators.Quote = []quoteJSON{{Close: closes, Volume: vol}}
	r.Chart.Result = append(r.Chart.Result, res)
	b, _ := json.Marshal(r)
	return b
}

func scanFixture() []byte {
	// reuse chart builder pattern — 210 bars ramp then drop
	closes := make([]float64, 210)
	for i := range closes {
		closes[i] = 100
	}
	closes[209] = 40
	return buildChart(closes)
}

func TestRun(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(scanFixture())
	}))
	defer srv.Close()
	orig := prices.BaseURL
	defer func() { prices.BaseURL = orig }()
	prices.BaseURL = srv.URL + "/prices"

	results := Run([]string{"PETR4", "XPTO3"}, nil)
	if len(results) != 2 {
		t.Fatalf("len=%d", len(results))
	}
	// failure row sorted last — tested in format tests; here just smoke
}
