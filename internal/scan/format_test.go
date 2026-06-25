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

func TestFormatJSON(t *testing.T) {
	results := []Result{{
		Ticker: "PETR4", Close: 38.42,
		Readings: Readings{RangePct: ptr(18), RSI: ptr(27)},
		Meta:     Meta{PeakDate: "2026-03-14", PeakClose: 49.2, SMA200: 43.6},
	}}
	out, err := FormatJSON("2026-06-25", results)
	if err != nil || !strings.Contains(out, `"range_pct": 18`) || !strings.Contains(out, `"as_of"`) {
		t.Fatalf("err=%v out=%q", err, out)
	}
}

func TestFormatDetail(t *testing.T) {
	r := Result{
		Ticker: "PETR4", Close: 38.42,
		Readings: Readings{
			RangePct: ptr(18), DrawdownPct: ptr(-22), SMA200Pct: ptr(-12),
			RSI: ptr(27), VolumeRatio: ptr(1.4),
		},
		Meta: Meta{PeakDate: "2026-03-14", PeakClose: 49.2, SMA200: 43.6},
	}
	out := FormatDetail(r)
	for _, want := range []string{"PETR4", "range", "18%", "drawdown", "rsi", "27", "volume", "1.4"} {
		if !strings.Contains(out, want) {
			t.Fatalf("missing %q in %q", want, out)
		}
	}
}
