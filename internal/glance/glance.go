// Package glance assembles and formats the per-ticker ignore/LOOK output.
package glance

import (
	"fmt"
	"strings"
	"time"

	"github.com/carvalhosauro/watchman/internal/anomaly"
	"github.com/carvalhosauro/watchman/internal/news"
	"github.com/carvalhosauro/watchman/internal/prices"
	"github.com/carvalhosauro/watchman/internal/verdict"
)

// Row is one ticker's verdict line.
type Row struct {
	Ticker string
	Look   bool
	Reason string
}

// BuildRow is the pure assembly: closes + fetch error + news flag → a verdict row.
func BuildRow(ticker string, closes []float64, fetchErr error, hasNews bool) Row {
	if fetchErr != nil {
		return Row{ticker, false, "no price data"}
	}
	a, err := anomaly.Analyze(closes)
	if err != nil {
		return Row{ticker, false, "not enough price history"}
	}
	d := verdict.Decide(a, hasNews)
	return Row{ticker, d.Look, d.Reason}
}

// Run is the impure path: one news fetch, then a price fetch per ticker.
func Run(tickers []string) []Row {
	items := news.FetchItems()
	today := time.Now().UTC().Format("2006-01-02")
	rows := make([]Row, 0, len(tickers))
	for _, t := range tickers {
		closes, err := prices.History(t)
		rows = append(rows, BuildRow(t, closes, err, news.Fresh(t, items, today)))
	}
	return rows
}

// Format renders rows into the one-screen glance.
func Format(rows []Row) string {
	var b strings.Builder
	for _, r := range rows {
		if r.Look {
			fmt.Fprintf(&b, "  ⚠ LOOK   %-8s %s\n", r.Ticker, r.Reason)
		} else {
			fmt.Fprintf(&b, "    ignore %-8s %s\n", r.Ticker, r.Reason)
		}
	}
	return b.String()
}
