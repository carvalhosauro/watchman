package scan

import (
	"strings"
	"testing"
)

func TestFormatTable(t *testing.T) {
	results := []Result{
		{Ticker: "PETR4", Close: 38, Readings: Readings{
			RangePct: ptr(18), DrawdownPct: ptr(-22), SMA200Pct: ptr(-12), RSI: ptr(27),
		}},
		{Ticker: "XPTO3", Error: "No data"},
	}
	out := FormatTable(results, 1)
	if !strings.Contains(out, "PETR4") || !strings.Contains(out, "18%") {
		t.Fatalf("missing PETR4 row: %q", out)
	}
	if !strings.Contains(out, "XPTO3") || !strings.Contains(out, "No data") {
		t.Fatalf("missing failure row: %q", out)
	}
}
