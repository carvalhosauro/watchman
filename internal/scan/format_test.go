package scan

import (
	"strings"
	"testing"
)

func TestFormatHeader(t *testing.T) {
	if got := FormatHeader("2026-06-25", 1); !strings.Contains(got, "(1 ticker)") {
		t.Fatalf("want singular ticker: %q", got)
	}
	if got := FormatHeader("2026-06-25", 4); !strings.Contains(got, "(4 tickers)") {
		t.Fatalf("want plural tickers: %q", got)
	}
}

func TestFormatTableBody(t *testing.T) {
	results := []Result{
		{Ticker: "PETR4", Close: ptr(38), Readings: &Readings{
			RangePct: ptr(18), DrawdownPct: ptr(-22), SMA200Pct: ptr(-12), RSI: ptr(27),
		}},
		{Ticker: "XPTO3", Error: "No data"},
	}
	out := FormatTableBody(results)
	if !strings.Contains(out, "PETR4") || !strings.Contains(out, "18%") {
		t.Fatalf("missing PETR4 row: %q", out)
	}
	if !strings.Contains(out, "XPTO3") || !strings.Contains(out, "No data") {
		t.Fatalf("missing failure row: %q", out)
	}
}

func TestFormatTableAlignment(t *testing.T) {
	results := []Result{
		{Ticker: "PETR4", Readings: &Readings{
			RangePct: ptr(44), DrawdownPct: ptr(-23), SMA200Pct: ptr(3), RSI: ptr(30),
		}},
		{Ticker: "MXRF11", Readings: &Readings{
			RangePct: ptr(100), DrawdownPct: ptr(-1), SMA200Pct: ptr(5), RSI: ptr(61),
		}},
		{Ticker: "BOGUS_TICKER_XYZ", Error: "API error"},
	}
	out := FormatTableBody(results)
	lines := strings.Split(strings.TrimRight(out, "\n"), "\n")
	if len(lines) < 4 {
		t.Fatalf("want header+3 rows, got %q", out)
	}
	rangeCol := strings.Index(lines[0], "RANGE")
	if rangeCol < 0 {
		t.Fatal("missing RANGE header")
	}
	for i, line := range lines[1:] {
		field := strings.TrimSpace(line[rangeCol:])
		if field == "" || field[0] == ' ' {
			t.Fatalf("row %d RANGE column not aligned: %q", i+1, line)
		}
	}
}

// TestFormatTableSignedTokens guards the #32 regression: the sign must stay glued
// to the digits in the DRAWDOWN / vs SMA200 columns (e.g. "−1%", "+3%"), never
// detached as "−  1%" / "+  3%". The alignment test above only inspects RANGE,
// which uses the unsigned formatter, so it cannot catch this.
func TestFormatTableSignedTokens(t *testing.T) {
	results := []Result{
		{Ticker: "AAA", Readings: &Readings{
			RangePct: ptr(5), DrawdownPct: ptr(-1), SMA200Pct: ptr(3), RSI: ptr(9),
		}},
	}
	out := FormatTableBody(results)
	for _, want := range []string{"−1%", "+3%"} {
		if !strings.Contains(out, want) {
			t.Fatalf("want clean signed token %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, "− ") || strings.Contains(out, "+ ") {
		t.Fatalf("sign detached from digits:\n%s", out)
	}
}

// TestFormatJSONClose guards the #M1 contract: a genuine close is present on
// success rows (a 0.0 close must not be dropped by omitempty).
func TestFormatJSONClose(t *testing.T) {
	results := []Result{{Ticker: "ZERO", Close: ptr(0), Readings: &Readings{RangePct: ptr(10)}}}
	out, err := FormatJSON("2026-06-25", results)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, `"close": 0`) {
		t.Fatalf("want close present on success row: %q", out)
	}
}

func TestFormatJSON(t *testing.T) {
	results := []Result{{
		Ticker: "PETR4", Close: ptr(38.42),
		Readings: &Readings{RangePct: ptr(18), RSI: ptr(27)},
		Meta:     &Meta{PeakDate: "2026-03-14", PeakClose: 49.2, SMA200: 43.6},
	}}
	out, err := FormatJSON("2026-06-25", results)
	if err != nil || !strings.Contains(out, `"range_pct": 18`) || !strings.Contains(out, `"as_of"`) {
		t.Fatalf("err=%v out=%q", err, out)
	}
}

func TestFormatJSONFailureRow(t *testing.T) {
	results := []Result{{Ticker: "BOGUS_TICKER_XYZ", Error: "API error"}}
	out, err := FormatJSON("2026-06-25", results)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out, `"readings"`) || strings.Contains(out, `"meta"`) || strings.Contains(out, `"close"`) {
		t.Fatalf("failure row should omit readings/meta/close: %q", out)
	}
	if !strings.Contains(out, `"error": "API error"`) {
		t.Fatalf("missing error field: %q", out)
	}
}

func TestFormatDetail(t *testing.T) {
	r := Result{
		Ticker: "PETR4", Close: ptr(38.42),
		Readings: &Readings{
			RangePct: ptr(18), DrawdownPct: ptr(-22), SMA200Pct: ptr(-12),
			RSI: ptr(27), VolumeRatio: ptr(1.4),
		},
		Meta: &Meta{PeakDate: "2026-03-14", PeakClose: 49.2, SMA200: 43.6},
	}
	out := FormatDetail(r)
	for _, want := range []string{"PETR4", "range", "18%", "drawdown", "rsi", "27", "volume", "1.4"} {
		if !strings.Contains(out, want) {
			t.Fatalf("missing %q in %q", want, out)
		}
	}
}

func TestFormatDetailAll(t *testing.T) {
	results := []Result{
		{Ticker: "A", Close: ptr(1), Readings: &Readings{RangePct: ptr(10)}},
		{Ticker: "B", Error: "No data"},
	}
	out := FormatDetailAll(results)
	if !strings.Contains(out, "A") || !strings.Contains(out, "B") || !strings.Contains(out, "No data") {
		t.Fatalf("got %q", out)
	}
}
