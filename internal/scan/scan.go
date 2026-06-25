// Package scan computes neutral technical readouts (range, drawdown, SMA200, RSI, volume)
// from price history without anomaly severity or verdict types.
package scan

import (
	"errors"
	"sort"

	"github.com/carvalhosauro/watchman/internal/prices"
)

// Readings holds optional indicator values; nil pointer = insufficient history.
type Readings struct {
	RangePct    *float64 `json:"range_pct,omitempty"`
	DrawdownPct *float64 `json:"drawdown_pct,omitempty"`
	SMA200Pct   *float64 `json:"sma200_pct,omitempty"`
	RSI         *float64 `json:"rsi,omitempty"`
	VolumeRatio *float64 `json:"volume_ratio,omitempty"`
}

// Meta carries factual context for detail/JSON output.
type Meta struct {
	PeakDate  string  `json:"peak_date,omitempty"`
	PeakClose float64 `json:"peak_close,omitempty"`
	SMA200    float64 `json:"sma200,omitempty"`
}

// Result is one ticker's scan row.
type Result struct {
	Ticker   string    `json:"ticker"`
	Close    *float64  `json:"close,omitempty"`
	Readings *Readings `json:"readings,omitempty"`
	Meta     *Meta     `json:"meta,omitempty"`
	Error    string    `json:"error,omitempty"`
}

const (
	// rankErr sorts fetch failures after all rows with data.
	rankErr = 1e9
	// rankNoRange sorts rows missing range below valid range values but above failures.
	rankNoRange = 1e8
)

func closeSeries(bars []prices.Bar) []float64 {
	out := make([]float64, len(bars))
	for i, b := range bars {
		out[i] = b.Close
	}
	return out
}

func ptr(f float64) *float64 { return &f }

// Evaluate computes all readings for one ticker from bars.
func Evaluate(ticker string, bars []prices.Bar) Result {
	r := Result{Ticker: ticker}
	if len(bars) == 0 {
		return r
	}
	r.Close = ptr(bars[len(bars)-1].Close)

	var readings Readings
	var meta Meta
	hasReading := false
	hasMeta := false

	if v, ok := rangePct(bars); ok {
		readings.RangePct = ptr(v)
		hasReading = true
	}
	if dd, peakDate, peakClose, ok := drawdownPct(bars); ok {
		readings.DrawdownPct = ptr(dd)
		meta.PeakDate = peakDate
		meta.PeakClose = peakClose
		hasReading = true
		hasMeta = true
	}
	if pct, sma, ok := sma200Pct(bars); ok {
		readings.SMA200Pct = ptr(pct)
		meta.SMA200 = sma
		hasReading = true
		hasMeta = true
	}
	if v, ok := rsiValue(bars); ok {
		readings.RSI = ptr(v)
		hasReading = true
	}
	if v, ok := volumeRatio(bars); ok {
		readings.VolumeRatio = ptr(v)
		hasReading = true
	}
	if hasReading {
		r.Readings = &readings
	}
	if hasMeta {
		r.Meta = &meta
	}
	return r
}

// BuildRow maps fetch outcome to a Result.
func BuildRow(ticker string, bars []prices.Bar, fetchErr error) Result {
	if fetchErr != nil {
		fail := "API error"
		if errors.Is(fetchErr, prices.ErrNoData) {
			fail = "No data"
		}
		return Result{Ticker: ticker, Error: fail}
	}
	return Evaluate(ticker, bars)
}

// Run fetches each ticker and returns scan results.
func Run(tickers []string, _ any) []Result {
	out := make([]Result, 0, len(tickers))
	for _, tk := range tickers {
		bars, err := prices.History(tk)
		out = append(out, BuildRow(tk, bars, err))
	}
	return sortResults(out)
}

func sortResults(in []Result) []Result {
	out := append([]Result(nil), in...)
	sort.SliceStable(out, func(i, j int) bool {
		return rank(out[i]) < rank(out[j])
	})
	return out
}

func rank(r Result) float64 {
	if r.Error != "" {
		return rankErr
	}
	if r.Readings == nil || r.Readings.RangePct == nil {
		return rankNoRange
	}
	return *r.Readings.RangePct
}
