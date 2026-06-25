package scan

import (
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
