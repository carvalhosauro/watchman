package scan

import (
	"encoding/json"
	"fmt"
	"strings"
	"text/tabwriter"
)

type jsonOut struct {
	AsOf    string   `json:"as_of"`
	Tickers []Result `json:"tickers"`
}

// FormatTable renders the human scan table (header line uses DATE placeholder — CLI adds real date).
func FormatTable(results []Result, tickerCount int) string {
	var b strings.Builder
	fmt.Fprintf(&b, "watchman scan — %s  (%d tickers)\n\n", "DATE", tickerCount)
	b.WriteString(FormatTableBody(results))
	return b.String()
}

// FormatTableBody renders table columns only (used by CLI with real date in header).
func FormatTableBody(results []Result) string {
	w := tabwriter.NewWriter(&strings.Builder{}, 0, 0, 2, ' ', 0)
	var b strings.Builder
	b.WriteString("TICKER   RANGE   DRAWDOWN   vs SMA200   RSI\n")
	for _, r := range results {
		if r.Error != "" {
			fmt.Fprintf(&b, "%-8s —       —          —           —       %s\n", r.Ticker, r.Error)
			continue
		}
		fmt.Fprintf(&b, "%-8s %s   %s   %s   %s\n",
			r.Ticker,
			fmtPct(r.Readings.RangePct),
			fmtPctSigned(r.Readings.DrawdownPct),
			fmtPctSigned(r.Readings.SMA200Pct),
			fmtNum(r.Readings.RSI, 0),
		)
	}
	_ = w
	return b.String()
}

func fmtPct(p *float64) string {
	if p == nil {
		return "—"
	}
	return fmt.Sprintf("%3.0f%%", *p)
}

func fmtPctSigned(p *float64) string {
	if p == nil {
		return "—"
	}
	return fmt.Sprintf("%+4.0f%%", *p)
}

func fmtNum(p *float64, prec int) string {
	if p == nil {
		return "—"
	}
	return fmt.Sprintf("%*.*f", 3+prec, prec, *p)
}

// FormatJSON renders scan results as indented JSON with an as_of timestamp.
func FormatJSON(asOf string, results []Result) (string, error) {
	payload := jsonOut{AsOf: asOf, Tickers: results}
	b, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return "", err
	}
	return string(b) + "\n", nil
}

// FormatDetail renders one ticker's expanded factual readout.
func FormatDetail(r Result) string {
	if r.Error != "" {
		return fmt.Sprintf("%s\n\n  error  %s\n", r.Ticker, r.Error)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s @ R$ %.2f\n\n", r.Ticker, r.Close)
	if r.Readings.RangePct != nil {
		fmt.Fprintf(&b, "  range     %3.0f%%   (position in 52-week low–high band)\n", *r.Readings.RangePct)
	}
	if r.Readings.DrawdownPct != nil {
		fmt.Fprintf(&b, "  drawdown  %+4.0f%%   (from peak R$ %.2f on %s)\n",
			*r.Readings.DrawdownPct, r.Meta.PeakClose, r.Meta.PeakDate)
	}
	if r.Readings.SMA200Pct != nil {
		fmt.Fprintf(&b, "  sma200    %+4.0f%%   (200-day average R$ %.2f)\n", *r.Readings.SMA200Pct, r.Meta.SMA200)
	}
	if r.Readings.RSI != nil {
		fmt.Fprintf(&b, "  rsi       %3.0f     (14-day Wilder)\n", *r.Readings.RSI)
	}
	if r.Readings.VolumeRatio != nil {
		fmt.Fprintf(&b, "  volume    %.1f×    (vs 20-day average)\n", *r.Readings.VolumeRatio)
	}
	return b.String()
}

// FormatDetailAll renders expanded readouts for every result.
func FormatDetailAll(results []Result) string {
	var b strings.Builder
	for i, r := range results {
		b.WriteString(FormatDetail(r))
		if i < len(results)-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}
