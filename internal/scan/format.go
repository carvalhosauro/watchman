package scan

import (
	"fmt"
	"strings"
	"text/tabwriter"
)

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
