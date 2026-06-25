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

// FormatHeader renders the scan title line with date and ticker count.
func FormatHeader(date string, tickerCount int) string {
	noun := "tickers"
	if tickerCount == 1 {
		noun = "ticker"
	}
	return fmt.Sprintf("watchman scan — %s  (%d %s)\n\n", date, tickerCount, noun)
}

// FormatTableBody renders aligned table columns (header + rows).
func FormatTableBody(results []Result) string {
	var buf strings.Builder
	w := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	_, _ = fmt.Fprintln(w, "TICKER\tRANGE\tDRAWDOWN\tvs SMA200\tRSI")
	for _, r := range results {
		if r.Error != "" {
			_, _ = fmt.Fprintf(w, "%s\t—\t—\t—\t—\t%s\n", r.Ticker, r.Error)
			continue
		}
		var rp, dp, sp, rsi *float64
		if r.Readings != nil {
			rp = r.Readings.RangePct
			dp = r.Readings.DrawdownPct
			sp = r.Readings.SMA200Pct
			rsi = r.Readings.RSI
		}
		_, _ = fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n",
			r.Ticker,
			fmtPct(rp),
			fmtPctSigned(dp),
			fmtPctSigned(sp),
			fmtNum(rsi),
		)
	}
	_ = w.Flush()
	return buf.String()
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
	v := *p
	if v >= 0 {
		return fmt.Sprintf("+%3.0f%%", v)
	}
	return fmt.Sprintf("−%3.0f%%", -v)
}

func fmtNum(p *float64) string {
	if p == nil {
		return "—"
	}
	return fmt.Sprintf("%3.0f", *p)
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
	if r.Readings != nil && r.Readings.RangePct != nil {
		fmt.Fprintf(&b, "  range     %3.0f%%   (position in 52-week low–high band)\n", *r.Readings.RangePct)
	}
	if r.Readings != nil && r.Readings.DrawdownPct != nil && r.Meta != nil {
		fmt.Fprintf(&b, "  drawdown  %s   (from peak R$ %.2f on %s)\n",
			fmtPctSigned(r.Readings.DrawdownPct), r.Meta.PeakClose, r.Meta.PeakDate)
	}
	if r.Readings != nil && r.Readings.SMA200Pct != nil && r.Meta != nil {
		fmt.Fprintf(&b, "  sma200    %s   (200-day average R$ %.2f)\n", fmtPctSigned(r.Readings.SMA200Pct), r.Meta.SMA200)
	}
	if r.Readings != nil && r.Readings.RSI != nil {
		fmt.Fprintf(&b, "  rsi       %3.0f     (14-day Wilder)\n", *r.Readings.RSI)
	}
	if r.Readings != nil && r.Readings.VolumeRatio != nil {
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
