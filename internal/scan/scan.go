package scan

import (
	"errors"

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
	Ticker   string   `json:"ticker"`
	Close    float64  `json:"close,omitempty"`
	Readings Readings `json:"readings,omitempty"`
	Meta     Meta     `json:"meta,omitempty"`
	Error    string   `json:"error,omitempty"`
}

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
	r.Close = bars[len(bars)-1].Close

	if v, ok := rangePct(bars); ok {
		r.Readings.RangePct = ptr(v)
	}
	if dd, peakDate, peakClose, ok := drawdownPct(bars); ok {
		r.Readings.DrawdownPct = ptr(dd)
		r.Meta.PeakDate = peakDate
		r.Meta.PeakClose = peakClose
	}
	if pct, sma, ok := sma200Pct(bars); ok {
		r.Readings.SMA200Pct = ptr(pct)
		r.Meta.SMA200 = sma
	}
	if v, ok := rsiValue(bars); ok {
		r.Readings.RSI = ptr(v)
	}
	if v, ok := volumeRatio(bars); ok {
		r.Readings.VolumeRatio = ptr(v)
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
