// Package glance assembles, ranks, and renders the per-ticker anomaly glance.
package glance

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/carvalhosauro/watchman/internal/prices"
	"github.com/carvalhosauro/watchman/internal/signals"
	"github.com/carvalhosauro/watchman/internal/verdict"
)

// Row is one ticker's verdict; Fail is non-empty when the fetch failed.
type Row struct {
	Ticker string
	Sev    signals.Severity
	Count  int
	Reason string
	Fail   string
	Sigs   []signals.Signal
	mag    float64
}

// BuildRow is the pure assembly: bars + fetch error → a ranked row.
func BuildRow(ticker string, bars []prices.Bar, fetchErr error, t signals.Thresholds) Row {
	if fetchErr != nil {
		fail := "API error"
		if errors.Is(fetchErr, prices.ErrNoData) {
			fail = "No data"
		}
		return Row{Ticker: ticker, Fail: fail}
	}
	sigs := signals.Evaluate(bars, t)
	d := verdict.Decide(sigs)
	mag := 0.0
	for _, s := range sigs {
		if s.Severity >= signals.Watch && math.Abs(s.Value) > mag {
			mag = math.Abs(s.Value)
		}
	}
	return Row{Ticker: ticker, Sev: d.Severity, Count: d.Count, Reason: d.Reason, Sigs: sigs, mag: mag}
}

// Run is the impure path: fetch each ticker, build its row.
func Run(tickers []string, t signals.Thresholds) []Row {
	rows := make([]Row, 0, len(tickers))
	for _, tk := range tickers {
		bars, err := prices.History(tk)
		rows = append(rows, BuildRow(tk, bars, err, t))
	}
	return rows
}

// OnlyAttention drops Calm rows but keeps failures and watch/LOOK rows.
func OnlyAttention(rows []Row) []Row {
	out := make([]Row, 0, len(rows))
	for _, r := range rows {
		if r.Fail != "" || r.Sev >= signals.Watch {
			out = append(out, r)
		}
	}
	return out
}

// Format renders rows worst-first. With detail, every signal is listed.
func Format(rows []Row, detail bool) string {
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].rank() != rows[j].rank() {
			return rows[i].rank() > rows[j].rank()
		}
		if rows[i].Count != rows[j].Count {
			return rows[i].Count > rows[j].Count
		}
		return rows[i].mag > rows[j].mag
	})
	var b strings.Builder
	for _, r := range rows {
		switch {
		case r.Fail != "":
			fmt.Fprintf(&b, "    —      %-8s %s\n", r.Ticker, r.Fail)
		case detail:
			fmt.Fprintf(&b, "  %-6s %-8s %s\n", label(r.Sev), r.Ticker, allSignals(r.Sigs))
		default:
			fmt.Fprintf(&b, "  %-6s %-8s %s\n", label(r.Sev), r.Ticker, r.Reason)
		}
	}
	return b.String()
}

// rank orders failures last, then by severity.
func (r Row) rank() int {
	if r.Fail != "" {
		return -1
	}
	return int(r.Sev)
}

func label(s signals.Severity) string {
	if s == signals.Look {
		return "⚠ LOOK"
	}
	return s.String()
}

func allSignals(sigs []signals.Signal) string {
	if len(sigs) == 0 {
		return "no signals"
	}
	parts := make([]string, len(sigs))
	for i, s := range sigs {
		parts[i] = s.Reason
	}
	return strings.Join(parts, " · ")
}
