# wm scan — Phase 1a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `wm scan` — a neutral technical readout over wallet tickers with human table output, `--detail`, and `--json` — backed by a new pure `internal/scan` package.

**Architecture:** `internal/scan` computes five factual readings (range, drawdown, sma200, rsi, volume) from `[]prices.Bar` without severity or verdict types. `BuildRow` classifies fetch failures like glance. `Run` fetches per ticker. Pure formatters render table/JSON/detail. `cmd/scan.go` wires cobra flags. `wm run` and wallet are untouched in this phase.

**Tech Stack:** Go 1.24+, cobra, stdlib `encoding/json` + `text/tabwriter`. Tests: table tests + `net/http/httptest` + testscript.

**Spec:** [`docs/superpowers/specs/2026-06-25-scan-opportunity-design.md`](../specs/2026-06-25-scan-opportunity-design.md) — this plan implements **phase 1a only** (not 1b explain/docs, not 1c wallet UX).

## Global Constraints

- Module `github.com/carvalhosauro/watchman`; binary `wm`; Go floor **1.24**.
- No DB, no config.toml changes, no new HTTP data sources.
- Do **not** import `internal/verdict` or `signals.Severity` into scan — duplicate small math helpers if needed.
- Every commit passes: `gofmt`, `goimports`, `golangci-lint run` (0 issues), `go test -race ./...`, coverage **≥80%** (`bash scripts/coverage.sh 80`).
- Conventional Commits; one commit per task.
- Branch: `cursor/scan-phase-1a-6eff` off `dev` (or continue from the spec branch if already open).

## File Map

| File | Responsibility |
|---|---|
| `internal/scan/scan.go` | Types (`Result`, `Readings`, `Meta`), `Evaluate`, `BuildRow`, `Run`, sort helper |
| `internal/scan/indicators.go` | Pure funcs: `rangePct`, `drawdownPct`, `sma200Pct`, `rsiValue`, `volumeRatio` |
| `internal/scan/format.go` | `FormatTable`, `FormatJSON`, `FormatDetail` |
| `internal/scan/scan_test.go` | Indicator + Evaluate + BuildRow tests |
| `internal/scan/format_test.go` | Formatter tests |
| `cmd/scan.go` | `wm scan` cobra command |
| `cmd/scan_test.go` | Optional thin CLI test (most coverage via testscript) |
| `cmd/wm/mock_test.go` | Extend mock with 210-bar scan series |
| `cmd/wm/testdata/script/scan.txtar` | Black-box CLI flows |

---

### Task 1: `internal/scan` types and bar helpers

**Files:**
- Create: `internal/scan/scan.go`
- Create: `internal/scan/scan_test.go`

**Interfaces produced:**
- `type Readings struct` with `RangePct`, `DrawdownPct`, `SMA200Pct`, `RSI`, `VolumeRatio` as `*float64` (nil = insufficient data).
- `type Meta struct { PeakDate string; PeakClose, SMA200 float64 }` — zero values when unknown.
- `type Result struct { Ticker string; Close float64; Readings Readings; Meta Meta; Error string }`.
- `func closeSeries(bars []prices.Bar) []float64`.
- `func barsWithDates(closes []float64, startDate string) []prices.Bar` — test helper only (in `_test.go`).

- [ ] **Step 1: Write the failing test** — `internal/scan/scan_test.go`

```go
package scan

import (
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func testBars(closes ...float64) []prices.Bar {
	out := make([]prices.Bar, len(closes))
	for i, c := range closes {
		out[i] = prices.Bar{Date: "2026-01-01", Close: c, Volume: 1000}
	}
	return out
}

func TestCloseSeries(t *testing.T) {
	got := closeSeries(testBars(10, 20, 30))
	if len(got) != 3 || got[2] != 30 {
		t.Fatalf("got %v", got)
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `go test ./internal/scan/ -run TestCloseSeries -v`  
Expected: FAIL — `closeSeries` undefined / package missing.

- [ ] **Step 3: Add types and helper** — `internal/scan/scan.go`

```go
package scan

import (
	"errors"

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
	Ticker   string    `json:"ticker"`
	Close    float64   `json:"close,omitempty"`
	Readings Readings  `json:"readings,omitempty"`
	Meta     Meta      `json:"meta,omitempty"`
	Error    string    `json:"error,omitempty"`
}

func closeSeries(bars []prices.Bar) []float64 {
	out := make([]float64, len(bars))
	for i, b := range bars {
		out[i] = b.Close
	}
	return out
}

func ptr(f float64) *float64 { return &f }
```

- [ ] **Step 4: Run test, expect PASS**

Run: `go test ./internal/scan/ -run TestCloseSeries -v`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/scan/scan.go internal/scan/scan_test.go
git commit -m "feat(scan): add Result types and bar helpers"
```

---

### Task 2: `range` indicator

**Files:**
- Create: `internal/scan/indicators.go`
- Modify: `internal/scan/scan_test.go`

**Definition:** `(close − low) / (high − low) × 100` over full series; requires **≥200** bars.

- [ ] **Step 1: Write failing tests** — append to `internal/scan/scan_test.go`

```go
func TestRangePct(t *testing.T) {
	lo := make([]float64, 200)
	for i := range lo {
		lo[i] = 10
	}
	lo[199] = 20 // close at high → 100%
	if v, ok := rangePct(testBars(lo...)); !ok || v < 99 {
		t.Fatalf("at high: got %v ok=%v", v, ok)
	}

	hi := make([]float64, 200)
	for i := range hi {
		hi[i] = 10 + float64(i)*0.1
	}
	// close near low of series after being high earlier — craft explicit:
	b := testBars(10, 20, 10, 20)
	b = b[:0]
	vals := make([]float64, 200)
	for i := range vals {
		vals[i] = 100
	}
	vals[199] = 10 // at low
	if v, ok := rangePct(testBars(vals...)); !ok || v > 1 {
		t.Fatalf("at low: got %v ok=%v", v, ok)
	}

	if _, ok := rangePct(testBars(10, 11)); ok {
		t.Fatal("want ok=false for <200 bars")
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `go test ./internal/scan/ -run TestRangePct -v`  
Expected: FAIL — `rangePct` undefined.

- [ ] **Step 3: Implement** — `internal/scan/indicators.go`

```go
package scan

import "github.com/carvalhosauro/watchman/internal/prices"

const rangeMinBars = 200

func rangePct(bars []prices.Bar) (float64, bool) {
	cs := closeSeries(bars)
	if len(cs) < rangeMinBars {
		return 0, false
	}
	hi, lo := cs[0], cs[0]
	for _, c := range cs {
		if c > hi {
			hi = c
		}
		if c < lo {
			lo = c
		}
	}
	if hi == lo {
		return 0, true
	}
	last := cs[len(cs)-1]
	return (last - lo) / (hi - lo) * 100, true
}
```

- [ ] **Step 4: Run, expect PASS**

Run: `go test ./internal/scan/ -run TestRangePct -v`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/scan/indicators.go internal/scan/scan_test.go
git commit -m "feat(scan): add range position indicator"
```

---

### Task 3: `drawdown` indicator (with peak meta)

**Files:**
- Modify: `internal/scan/indicators.go`
- Modify: `internal/scan/scan_test.go`

**Definition:** `(close − peak) / peak × 100`; requires **≥2** bars. Also returns peak date/close for `Meta`.

- [ ] **Step 1: Write failing test**

```go
func TestDrawdownPct(t *testing.T) {
	b := testBars(10, 20, 18, 15)
	b[1].Date = "2026-03-14"
	dd, peakDate, peakClose, ok := drawdownPct(b)
	if !ok || dd > -10 || peakClose != 20 || peakDate != "2026-03-14" {
		t.Fatalf("got dd=%v peak=%v@%v ok=%v", dd, peakClose, peakDate, ok)
	}
	if _, _, _, ok := drawdownPct(testBars(10)); ok {
		t.Fatal("want ok=false for 1 bar")
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `go test ./internal/scan/ -run TestDrawdownPct -v`

- [ ] **Step 3: Implement** — append to `internal/scan/indicators.go`

```go
func drawdownPct(bars []prices.Bar) (pct float64, peakDate string, peakClose float64, ok bool) {
	if len(bars) < 2 {
		return 0, "", 0, false
	}
	peak := bars[0].Close
	peakDate = bars[0].Date
	for _, b := range bars {
		if b.Close > peak {
			peak = b.Close
			peakDate = b.Date
		}
	}
	last := bars[len(bars)-1].Close
	if peak == 0 {
		return 0, peakDate, peak, true
	}
	return (last - peak) / peak * 100, peakDate, peak, true
}
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add drawdown indicator with peak meta"
```

---

### Task 4: `sma200` indicator

**Files:**
- Modify: `internal/scan/indicators.go`
- Modify: `internal/scan/scan_test.go`

**Definition:** `(close − SMA200) / SMA200 × 100`; requires **≥200** bars.

- [ ] **Step 1: Write failing test**

```go
func TestSMA200Pct(t *testing.T) {
	vals := make([]float64, 200)
	for i := range vals {
		vals[i] = 100
	}
	vals[199] = 110 // +10% above SMA200 of 100s... SMA of 100..99,100 with last 110
	b := testBars(vals...)
	pct, sma, ok := sma200Pct(b)
	if !ok || sma == 0 {
		t.Fatalf("got pct=%v sma=%v ok=%v", pct, sma, ok)
	}
	if pct <= 0 {
		t.Fatalf("want positive pct above sma, got %v", pct)
	}
	if _, _, ok := sma200Pct(testBars(10, 11)); ok {
		t.Fatal("want ok=false for <200 bars")
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement**

```go
const sma200Window = 200

func sma200Pct(bars []prices.Bar) (pct float64, sma float64, ok bool) {
	cs := closeSeries(bars)
	if len(cs) < sma200Window {
		return 0, 0, false
	}
	window := cs[len(cs)-sma200Window:]
	sum := 0.0
	for _, c := range window {
		sum += c
	}
	sma = sum / float64(sma200Window)
	last := cs[len(cs)-1]
	if sma == 0 {
		return 0, sma, true
	}
	return (last - sma) / sma * 100, sma, true
}
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add SMA200 distance indicator"
```

---

### Task 5: `rsi` indicator (Wilder 14)

**Files:**
- Modify: `internal/scan/indicators.go`
- Modify: `internal/scan/scan_test.go`

**Definition:** Same algorithm as `internal/signals/rsi.go` (Wilder RSI(14)); requires **≥15** closes.

- [ ] **Step 1: Write failing test**

```go
func TestRSIValue(t *testing.T) {
	up := make([]float64, 20)
	for i := range up {
		up[i] = 10 + float64(i)
	}
	v, ok := rsiValue(testBars(up...))
	if !ok || v <= 80 {
		t.Fatalf("monotonic up: got %v ok=%v", v, ok)
	}
	if _, ok := rsiValue(testBars(10, 11)); ok {
		t.Fatal("want ok=false for <15 bars")
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement** — duplicate Wilder logic (do not import signals)

```go
const rsiPeriod = 14

func rsiValue(bars []prices.Bar) (float64, bool) {
	cs := closeSeries(bars)
	if len(cs) < rsiPeriod+1 {
		return 0, false
	}
	var gain, loss float64
	for i := 1; i <= rsiPeriod; i++ {
		d := cs[i] - cs[i-1]
		if d >= 0 {
			gain += d
		} else {
			loss -= d
		}
	}
	avgGain, avgLoss := gain/rsiPeriod, loss/rsiPeriod
	for i := rsiPeriod + 1; i < len(cs); i++ {
		d := cs[i] - cs[i-1]
		g, l := 0.0, 0.0
		if d >= 0 {
			g = d
		} else {
			l = -d
		}
		avgGain = (avgGain*(rsiPeriod-1) + g) / rsiPeriod
		avgLoss = (avgLoss*(rsiPeriod-1) + l) / rsiPeriod
	}
	if avgLoss == 0 {
		return 100, true
	}
	return 100 - 100/(1+avgGain/avgLoss), true
}
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add RSI(14) indicator"
```

---

### Task 6: `volume` indicator

**Files:**
- Modify: `internal/scan/indicators.go`
- Modify: `internal/scan/scan_test.go`

**Definition:** latest volume ÷ 20-day average; requires **≥21** bars with volume.

- [ ] **Step 1: Write failing test**

```go
func volBars(vols ...float64) []prices.Bar {
	out := make([]prices.Bar, len(vols))
	for i, v := range vols {
		out[i] = prices.Bar{Close: 10, Volume: v}
	}
	return out
}

func TestVolumeRatio(t *testing.T) {
	vols := make([]float64, 21)
	for i := range vols {
		vols[i] = 1000
	}
	vols[20] = 3000
	r, ok := volumeRatio(volBars(vols...))
	if !ok || r < 2.9 {
		t.Fatalf("got %v ok=%v", r, ok)
	}
	if _, ok := volumeRatio(volBars(1000)); ok {
		t.Fatal("want ok=false for <21 bars")
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement**

```go
const volWindow = 20

func volumeRatio(bars []prices.Bar) (float64, bool) {
	if len(bars) < volWindow+1 {
		return 0, false
	}
	window := bars[len(bars)-volWindow-1 : len(bars)-1]
	var sum float64
	for _, b := range window {
		sum += b.Volume
	}
	avg := sum / float64(volWindow)
	if avg == 0 {
		return 0, false
	}
	return bars[len(bars)-1].Volume / avg, true
}
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add volume ratio indicator"
```

---

### Task 7: `Evaluate` and `BuildRow`

**Files:**
- Modify: `internal/scan/scan.go`
- Modify: `internal/scan/scan_test.go`

- [ ] **Step 1: Write failing test**

```go
import (
	"errors"
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func TestEvaluate(t *testing.T) {
	vals := make([]float64, 210)
	for i := range vals {
		vals[i] = 100
	}
	vals[209] = 50
	b := testBars(vals...)
	r := Evaluate("TEST", b)
	if r.Ticker != "TEST" || r.Close != 50 {
		t.Fatalf("got %+v", r)
	}
	if r.Readings.RangePct == nil || r.Readings.DrawdownPct == nil {
		t.Fatalf("want range+drawdown, got %+v", r.Readings)
	}
}

func TestBuildRowNoData(t *testing.T) {
	r := BuildRow("X", nil, prices.ErrNoData)
	if r.Error != "No data" {
		t.Fatalf("got %+v", r)
	}
}

func TestBuildRowAPIError(t *testing.T) {
	r := BuildRow("X", nil, errors.New("http 500"))
	if r.Error != "API error" {
		t.Fatalf("got %+v", r)
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `go test ./internal/scan/ -run 'TestEvaluate|TestBuildRow' -v`

- [ ] **Step 3: Implement** — append to `internal/scan/scan.go`

```go
import (
	"errors"

	"github.com/carvalhosauro/watchman/internal/prices"
)

// Evaluate computes all readings for one ticker from bars.
func Evaluate(ticker string, bars []prices.Bar) Result {
	r := Result{Ticker: ticker}
	if len(bars) == 0 {
		return r
	}
	r.Close = bars[len(bars)-1].Close

	if v, ok := rangePct(bars); ok {
		r.Readings.RangePct = ptr(v)
	}
	if dd, peakDate, peakClose, ok := drawdownPct(bars); ok {
		r.Readings.DrawdownPct = ptr(dd)
		r.Meta.PeakDate = peakDate
		r.Meta.PeakClose = peakClose
	}
	if pct, sma, ok := sma200Pct(bars); ok {
		r.Readings.SMA200Pct = ptr(pct)
		r.Meta.SMA200 = sma
	}
	if v, ok := rsiValue(bars); ok {
		r.Readings.RSI = ptr(v)
	}
	if v, ok := volumeRatio(bars); ok {
		r.Readings.VolumeRatio = ptr(v)
	}
	return r
}

// BuildRow maps fetch outcome to a Result.
func BuildRow(ticker string, bars []prices.Bar, fetchErr error) Result {
	if fetchErr != nil {
		fail := "API error"
		if errors.Is(fetchErr, prices.ErrNoData) {
			fail = "No data"
		}
		return Result{Ticker: ticker, Error: fail}
	}
	return Evaluate(ticker, bars)
}
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add Evaluate and BuildRow"
```

---

### Task 8: `Run` and sort

**Files:**
- Modify: `internal/scan/scan.go`
- Modify: `internal/scan/scan_test.go`

- [ ] **Step 1: Write failing test** — uses httptest (add to `scan_test.go`)

```go
import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func scanFixture() []byte {
	// reuse chart builder pattern — 210 bars ramp then drop
	closes := make([]float64, 210)
	for i := range closes {
		closes[i] = 100
	}
	closes[209] = 40
	return buildChart(closes) // implement minimal JSON builder in test file
}

func TestRun(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(scanFixture())
	}))
	defer srv.Close()
	orig := prices.BaseURL
	defer func() { prices.BaseURL = orig }()
	prices.BaseURL = srv.URL + "/prices"

	results := Run([]string{"PETR4", "XPTO3"}, nil)
	if len(results) != 2 {
		t.Fatalf("len=%d", len(results))
	}
	// failure row sorted last — tested in format tests; here just smoke
}
```

Add `buildChart` helper in test file (copy from `cmd/wm/mock_test.go` `chart` function).

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement**

```go
// Run fetches each ticker and returns scan results.
func Run(tickers []string, _ any) []Result {
	out := make([]Result, 0, len(tickers))
	for _, tk := range tickers {
		bars, err := prices.History(tk)
		out = append(out, BuildRow(tk, bars, err))
	}
	return SortResults(out)
}

// SortResults orders by range ascending; failures last; nil range after valid.
func SortResults(in []Result) []Result {
	out := append([]Result(nil), in...)
	sort.SliceStable(out, func(i, j int) bool {
		return rank(out[i]) < rank(out[j])
	})
	return out
}

func rank(r Result) float64 {
	if r.Error != "" {
		return 1e9
	}
	if r.Readings.RangePct == nil {
		return 1e8
	}
	return *r.Readings.RangePct
}
```

Add `"sort"` to imports in `scan.go`.

- [ ] **Step 4: Run, expect PASS**

Run: `go test ./internal/scan/ -run TestRun -v`

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add Run with range-ascending sort"
```

---

### Task 9: `FormatTable`

**Files:**
- Create: `internal/scan/format.go`
- Create: `internal/scan/format_test.go`

- [ ] **Step 1: Write failing test**

```go
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
```

- [ ] **Step 2: Run, expect FAIL**

Run: `go test ./internal/scan/ -run TestFormatTable -v`

- [ ] **Step 3: Implement** — `internal/scan/format.go`

```go
package scan

import (
	"fmt"
	"strings"
	"text/tabwriter"
)

// FormatTable renders the human scan table (header line excluded — CLI adds date).
func FormatTable(results []Result, tickerCount int) string {
	var b strings.Builder
	fmt.Fprintf(&b, "watchman scan — %s  (%d tickers)\n\n", "DATE", tickerCount)
	// CLI replaces DATE; export a helper:
	return formatTableBody(results)
}

// formatTableBody renders columns only (used by CLI with real date).
func formatTableBody(results []Result) string {
	w := tabwriter.NewWriter(&strings.Builder{}, 0, 0, 2, ' ', 0)
	// Use manual fmt alignment to match spec (tabwriter optional):
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
```

Refactor: expose `FormatTableResults(results []Result) string` for body; CLI adds header with date. Adjust test accordingly.

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git add internal/scan/format.go internal/scan/format_test.go
git commit -m "feat(scan): add table formatter"
```

---

### Task 10: `FormatJSON`

**Files:**
- Modify: `internal/scan/format.go`
- Modify: `internal/scan/format_test.go`

- [ ] **Step 1: Write failing test**

```go
func TestFormatJSON(t *testing.T) {
	results := []Result{{
		Ticker: "PETR4", Close: 38.42,
		Readings: Readings{RangePct: ptr(18), RSI: ptr(27)},
		Meta:     Meta{PeakDate: "2026-03-14", PeakClose: 49.2, SMA200: 43.6},
	}}
	out, err := FormatJSON("2026-06-25", results)
	if err != nil || !strings.Contains(out, `"range_pct":18`) || !strings.Contains(out, `"as_of"`) {
		t.Fatalf("err=%v out=%q", err, out)
	}
}
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement**

```go
import "encoding/json"

type jsonOut struct {
	AsOf    string   `json:"as_of"`
	Tickers []Result `json:"tickers"`
}

func FormatJSON(asOf string, results []Result) (string, error) {
	payload := jsonOut{AsOf: asOf, Tickers: results}
	b, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return "", err
	}
	return string(b) + "\n", nil
}
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add JSON formatter"
```

---

### Task 11: `FormatDetail`

**Files:**
- Modify: `internal/scan/format.go`
- Modify: `internal/scan/format_test.go`

- [ ] **Step 1: Write failing test**

```go
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
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement**

```go
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
```

- [ ] **Step 4: Run, expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(scan): add detail formatter"
```

---

### Task 12: `cmd/scan.go` CLI wiring

**Files:**
- Create: `cmd/scan.go`
- Mirror: `cmd/run.go` patterns

- [ ] **Step 1: Add command** — `cmd/scan.go`

```go
package cmd

import (
	"fmt"
	"time"

	"github.com/carvalhosauro/watchman/internal/scan"
	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	var detail, asJSON bool
	cmd := &cobra.Command{
		Use:   "scan [TICKER...]",
		Short: "show neutral technical readout for watched tickers",
		RunE: func(cmd *cobra.Command, args []string) error {
			out := cmd.OutOrStdout()
			tickers := args
			if len(tickers) == 0 {
				ts, err := wallet.List(wallet.Path())
				if err != nil {
					return err
				}
				tickers = ts
			}
			if len(tickers) == 0 {
				_, _ = fmt.Fprintln(out, "No tickers. Add with: wm wallet add PETR4")
				return nil
			}
			results := scan.Run(tickers, nil)
			date := time.Now().UTC().Format("2006-01-02")
			if asJSON {
				s, err := scan.FormatJSON(date, results)
				if err != nil {
					return err
				}
				_, _ = fmt.Fprint(out, s)
				return nil
			}
			if detail {
				_, _ = fmt.Fprintf(out, "watchman scan — %s  (%d tickers)\n\n", date, len(tickers))
				_, _ = fmt.Fprint(out, scan.FormatDetailAll(results))
				return nil
			}
			_, _ = fmt.Fprintf(out, "watchman scan — %s  (%d tickers)\n\n", date, len(tickers))
			_, _ = fmt.Fprint(out, scan.FormatTableBody(results))
			return nil
		},
	}
	cmd.Flags().BoolVar(&detail, "detail", false, "expanded per-ticker readout")
	cmd.Flags().BoolVar(&asJSON, "json", false, "machine-readable JSON output")
	rootCmd.AddCommand(cmd)
}
```

Export `FormatTableBody` from `internal/scan/format.go` (rename from unexported helper).

- [ ] **Step 2: Build binary**

Run: `make build`  
Expected: succeeds, `bin/wm scan --help` shows flags.

- [ ] **Step 3: Commit**

```bash
git add cmd/scan.go internal/scan/format.go
git commit -m "feat(scan): add wm scan command"
```

---

### Task 13: Extend mock server + unit test

**Files:**
- Modify: `cmd/wm/mock_test.go`

- [ ] **Step 1: Add 210-bar scan series and test**

```go
func scanSeries() []float64 {
	s := make([]float64, 210)
	for i := range s {
		s[i] = 100
	}
	s[209] = 40 // deep in range band
	return s
}

func TestMockDrivesScan(t *testing.T) {
	srv := newMockServer(t)
	orig := prices.BaseURL
	t.Cleanup(func() { prices.BaseURL = orig })
	prices.BaseURL = srv.URL + "/prices"

	results := scan.Run([]string{"PETR4", "XPTO3"}, nil)
	got := map[string]scan.Result{}
	for _, r := range results {
		got[r.Ticker] = r
	}
	if got["XPTO3"].Error != "No data" {
		t.Errorf("XPTO3 = %+v want No data", got["XPTO3"])
	}
	if got["PETR4"].Error != "" || got["PETR4"].Readings.RangePct == nil {
		t.Errorf("PETR4 = %+v want readings", got["PETR4"])
	}
}
```

Update `newMockServer` so `PETR4` serves `scanSeries()` (210 bars) — keeps glance test working if PETR4 still abnormal for z-score OR update glance test to use a different ticker. **Resolution:** serve `scanSeries()` for PETR4; move glance abnormal case to `ABCD4` path in mock; update `TestMockDrivesGlance` and `run.txtar` if they assert PETR4 — check `run.txtar` expects PETR4 LOOK. **Keep PETR4 as abnormal for run.txtar**; add `SCAN1` ticker route for scan tests only.

Mock routing addition:

```go
case strings.Contains(r.URL.Path, "SCAN1"):
	_, _ = w.Write(chart(scanSeries()))
```

Use `SCAN1` in scan tests and txtar, leave PETR4 for run.

- [ ] **Step 2: Run tests**

Run: `go test -race ./cmd/wm/ -run TestMockDrivesScan -v`  
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git commit -am "test(scan): add mock-driven scan integration test"
```

---

### Task 14: testscript `scan.txtar`

**Files:**
- Create: `cmd/wm/testdata/script/scan.txtar`

- [ ] **Step 1: Write script**

```text
# wm scan table against mock upstream
cp wallet_seed wallet
wm scan SCAN1
stdout 'watchman scan'
stdout 'SCAN1'
stdout 'RANGE'

# JSON output
wm scan SCAN1 --json
stdout '"ticker": "SCAN1"'
stdout '"as_of"'

# detail mode
wm scan SCAN1 --detail
stdout 'position in 52-week'

# failure row
wm scan XPTO3
stdout 'XPTO3'
stdout 'No data'

# empty wallet hint
env WATCHMAN_WALLET=$WORK/empty
wm scan
stdout 'No tickers'

-- wallet_seed --
SCAN1
XPTO3
```

- [ ] **Step 2: Run testscript**

Run: `go test -race ./cmd/wm/ -run TestScripts -v`  
Expected: PASS (all txtar files including new scan.txtar).

- [ ] **Step 3: Commit**

```bash
git add cmd/wm/testdata/script/scan.txtar
git commit -m "test(scan): add testscript flows"
```

---

### Task 15: README + ROADMAP + CI gate

**Files:**
- Modify: `README.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: Document `wm scan` in README** — add section after `wm run`:

```markdown
wm scan                   # neutral technical readout (RANGE, DRAWDOWN, vs SMA200, RSI)
wm scan SCAN1             # single ticker
wm scan --detail SCAN1    # expanded factual context
wm scan --json            # machine-readable output
```

Add to "What it doesn't do": still no advice; scan shows numbers only.

- [ ] **Step 2: Mark phase 1a done in ROADMAP** — change scan bullet to *Done* when shipped.

- [ ] **Step 3: Run full CI gate**

Run: `make ci`  
Expected: PASS, coverage ≥80%.

- [ ] **Step 4: Commit**

```bash
git add README.md ROADMAP.md
git commit -m "docs: document wm scan (phase 1a)"
```

---

## Spec Coverage Checklist (phase 1a)

| Spec requirement | Task |
|---|---|
| `internal/scan` package with 5 indicators | Tasks 2–6 |
| `Evaluate` / `BuildRow` / `Run` | Tasks 7–8 |
| Failure taxonomy No data / API error | Task 7 |
| Sort by range ascending | Task 8 |
| Table output | Task 9 |
| `--json` output | Tasks 10, 12 |
| `--detail` output | Tasks 11, 12 |
| Empty wallet message | Task 12 |
| No changes to `wm run` | — (no tasks touch run) |
| testscript + httptest | Tasks 13–14 |
| Coverage ≥80% | Task 15 |
| README update | Task 15 |

**Explicitly deferred to later phases:** `wm explain`, `docs/indicators/`, wallet multi-add/clear, history NDJSON, schedule.

## Self-Review Notes

- `FormatTable` header date is assembled in CLI, not the formatter — keeps formatters pure and testable.
- Mock uses ticker `SCAN1` to avoid breaking existing `run.txtar` PETR4 LOOK assertions.
- RSI math is duplicated from `internal/signals` intentionally to keep scan independent of anomaly severity types.
- `Run(tickers, nil)` second arg reserved for future config; pass `nil` in 1a.
