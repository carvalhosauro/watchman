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
	return fmt.Sprintf("%.0f%%", *p)
}

// fmtPctSigned keeps the sign glued to the digits (e.g. "−1%", "+3%"); column
// padding is left to tabwriter so single- and multi-digit values stay aligned.
func fmtPctSigned(p *float64) string {
	if p == nil {
		return "—"
	}
	v := *p
	if v < 0 {
		return fmt.Sprintf("−%.0f%%", -v)
	}
	return fmt.Sprintf("+%.0f%%", v)
}

func fmtNum(p *float64) string {
	if p == nil {
		return "—"
	}
	return fmt.Sprintf("%.0f", *p)
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

// FormatDetail renders one ticker's expanded factual readout. Indicator lines are
// tab-aligned so the parenthetical context columns line up regardless of value width
// (tabwriter measures runes, so the Unicode minus does not skew alignment).
func FormatDetail(r Result) string {
	if r.Error != "" {
		return fmt.Sprintf("%s\n\n  error  %s\n", r.Ticker, r.Error)
	}
	var b strings.Builder
	closeVal := 0.0
	if r.Close != nil {
		closeVal = *r.Close
	}
	fmt.Fprintf(&b, "%s @ R$ %.2f\n\n", r.Ticker, closeVal)
	w := tabwriter.NewWriter(&b, 0, 0, 3, ' ', 0)
	if r.Readings != nil && r.Readings.RangePct != nil {
		_, _ = fmt.Fprintf(w, "  range\t%s\t(position in 52-week low–high band)\n", fmtPct(r.Readings.RangePct))
	}
	if r.Readings != nil && r.Readings.DrawdownPct != nil && r.Meta != nil {
		_, _ = fmt.Fprintf(w, "  drawdown\t%s\t(from peak R$ %.2f on %s)\n",
			fmtPctSigned(r.Readings.DrawdownPct), r.Meta.PeakClose, r.Meta.PeakDate)
	}
	if r.Readings != nil && r.Readings.SMA200Pct != nil && r.Meta != nil {
		_, _ = fmt.Fprintf(w, "  sma200\t%s\t(200-day average R$ %.2f)\n", fmtPctSigned(r.Readings.SMA200Pct), r.Meta.SMA200)
	}
	if r.Readings != nil && r.Readings.RSI != nil {
		_, _ = fmt.Fprintf(w, "  rsi\t%s\t(14-day Wilder)\n", fmtNum(r.Readings.RSI))
	}
	if r.Readings != nil && r.Readings.VolumeRatio != nil {
		_, _ = fmt.Fprintf(w, "  volume\t%.1f×\t(vs 20-day average)\n", *r.Readings.VolumeRatio)
	}
	_ = w.Flush()
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
