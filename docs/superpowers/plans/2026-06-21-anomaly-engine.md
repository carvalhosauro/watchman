# Anomaly Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Model routing (deep-plan):** Plan = Opus xhigh | Exec atômica = Sonnet high | Exec complexa = Opus xhigh | Review = Opus xhigh | Final = Opus xhigh

**Goal:** Replace watchman's single z-score + news verdict with a deterministic multi-signal price/volume anomaly engine (zscore, RSI, drawdown, 52-week proximity, volume), with user-tunable thresholds, typed failure messages, and a detailed mode.

**Architecture:** `prices` returns 1-year `[]Bar` (close+volume). A new pure `signals` package computes each indicator into a `Signal{Name,Value,Severity,Reason}`; `signals.Evaluate` returns all of them (incl. Calm). `verdict.Decide` reduces them to a severity + count. `glance` ranks rows worst-first and renders; `config` loads tunable thresholds from TOML. `internal/news` and `internal/anomaly` are deleted.

**Tech Stack:** Go 1.24+, cobra, stdlib net/http + encoding/json, `github.com/BurntSushi/toml`. Tests: table tests + `net/http/httptest` + testscript.

## Global Constraints

- Module `github.com/carvalhosauro/watchman`; binary `wm`; Go floor **1.24**.
- No DB, no new data source beyond Yahoo. Pure logic isolated from I/O.
- Every commit passes gates: `gofmt`, `golangci-lint run` (0 issues), `go test -race ./...`, coverage **≥80** (`bash scripts/coverage.sh 80`). Conventional Commits; one commit per task.
- Thresholds are user-tunable via `~/.config/watchman/config.toml` (`WATCHMAN_CONFIG` override); missing file/key → built-in default.
- Failures are classified: `prices.ErrNoData` → "No data"; any other error → "API error".
- Branch `feat/anomaly-engine`. CLI surface stays `wm wallet …` / `wm run`; ship v2.1.0.

---

### Task 1: `prices` returns 1-year bars with volume

**Files:**
- Modify: `internal/prices/prices.go`
- Modify: `internal/prices/prices_test.go`

**Interfaces:**
- Produces: `type Bar struct { Date string; Close, Volume float64 }`; `History(ticker string) ([]Bar, error)`; `var ErrNoData` (unchanged); `var BaseURL`.

- [ ] **Step 1: Replace the parse test** — `internal/prices/prices_test.go` (replace the `fixture`/`TestParse` block; keep `TestEnvURL`, `TestHistoryFlow`, `TestHistoryHTTPError` but update them to `[]Bar`)

```go
const fixture = `{"chart":{"error":null,"result":[{"timestamp":[1718000000,1718086400,1718172800],"indicators":{"quote":[{"close":[10.0,null,11.0],"volume":[100,200,300]}]}}]}}`

func TestParse(t *testing.T) {
	got, err := Parse([]byte(fixture))
	if err != nil {
		t.Fatal(err)
	}
	// the null-close bar is dropped; two bars remain, oldest→newest
	if len(got) != 2 || got[0].Close != 10.0 || got[1].Close != 11.0 || got[1].Volume != 300 {
		t.Fatalf("got %+v", got)
	}
}

func TestParseError(t *testing.T) {
	if _, err := Parse([]byte(`{"chart":{"error":"Not Found","result":null}}`)); err != ErrNoData {
		t.Fatalf("want ErrNoData got %v", err)
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/prices/ -run TestParse -v` → FAIL (Parse returns `[]float64`).

- [ ] **Step 3: Rewrite parse + History** — `internal/prices/prices.go` (replace `chartResp`, `Parse`, `History`)

```go
type chartResp struct {
	Chart struct {
		Error  any `json:"error"`
		Result []struct {
			Timestamp  []int64 `json:"timestamp"`
			Indicators struct {
				Quote []struct {
					Close  []*float64 `json:"close"`
					Volume []*float64 `json:"volume"`
				} `json:"quote"`
			} `json:"indicators"`
		} `json:"result"`
	} `json:"chart"`
}

// Bar is one trading day's close and volume.
type Bar struct {
	Date   string
	Close  float64
	Volume float64
}

// Parse extracts daily bars (oldest→newest) from a Yahoo chart payload; bars
// with a null close are dropped.
func Parse(body []byte) ([]Bar, error) {
	var r chartResp
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, err
	}
	if r.Chart.Error != nil {
		return nil, ErrNoData
	}
	if len(r.Chart.Result) == 0 || len(r.Chart.Result[0].Indicators.Quote) == 0 {
		return nil, ErrNoData
	}
	res := r.Chart.Result[0]
	q := res.Indicators.Quote[0]
	out := make([]Bar, 0, len(q.Close))
	for i, c := range q.Close {
		if c == nil {
			continue
		}
		b := Bar{Close: *c}
		if i < len(res.Timestamp) {
			b.Date = time.Unix(res.Timestamp[i], 0).UTC().Format("2006-01-02")
		}
		if i < len(q.Volume) && q.Volume[i] != nil {
			b.Volume = *q.Volume[i]
		}
		out = append(out, b)
	}
	if len(out) == 0 {
		return nil, ErrNoData
	}
	return out, nil
}

// History fetches ~1 year of daily bars for ticker from Yahoo Finance.
func History(ticker string) ([]Bar, error) {
	url := fmt.Sprintf("%s/%s.SA?range=1y&interval=1d", BaseURL, ticker)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "watchman/2.0")
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http %d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return Parse(body)
}
```
Add `"time"` to the import block.

- [ ] **Step 4: Update the flow tests** — in `prices_test.go`, `TestHistoryFlow` should assert `[]Bar`:

```go
func TestHistoryFlow(t *testing.T) {
	orig := BaseURL
	t.Cleanup(func() { BaseURL = orig })
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("User-Agent") == "" {
			t.Error("missing User-Agent")
		}
		_, _ = w.Write([]byte(fixture))
	}))
	defer srv.Close()
	BaseURL = srv.URL
	got, err := History("PETR4")
	if err != nil || len(got) != 2 || got[1].Close != 11.0 {
		t.Fatalf("got %+v err %v", got, err)
	}
}
```
(`TestHistoryHTTPError` and `TestEnvURL` are unchanged.)

- [ ] **Step 5: Run** — `go test ./internal/prices/ -v` → PASS.
- [ ] **Step 6: Commit** — `git add internal/prices && git commit -m "feat(prices): return 1y bars with volume"`

**✅ Done when:** `go test ./internal/prices/ -v` passes; `Parse` drops null-close bars and reads volume+date; `History` fetches `range=1y`.

> Note: this breaks `internal/anomaly` and `internal/glance` compilation (they use the old `[]float64`). They are rewritten/deleted in Tasks 8–10; until then `go build ./...` is red. Run package-scoped tests per task; the tree returns green at Task 10.

---

### Task 2: `signals` package — types, defaults, zscore

**Files:**
- Create: `internal/signals/signals.go`
- Create: `internal/signals/zscore.go`
- Create: `internal/signals/signals_test.go`

**Interfaces:**
- Produces: `type Severity int` (`Calm`,`Watch`,`Look`); `func (Severity) String() string`; `type Signal struct { Name string; Value float64; Severity Severity; Reason string }`; `type Thresholds struct {...}`; `func Defaults() Thresholds`; `func zscore(bars []prices.Bar, t Thresholds) (Signal, bool)`.

- [ ] **Step 1: Failing test** — `internal/signals/signals_test.go`

```go
package signals

import (
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
)

func bars(closes ...float64) []prices.Bar {
	out := make([]prices.Bar, len(closes))
	for i, c := range closes {
		out[i] = prices.Bar{Close: c, Volume: 1000}
	}
	return out
}

func TestZScore(t *testing.T) {
	flat := make([]float64, 30)
	for i := range flat {
		flat[i] = 10
	}
	jump := append(append([]float64{}, flat...), 13) // +30% after flat
	s, ok := zscore(bars(jump...), Defaults())
	if !ok || s.Severity != Look {
		t.Fatalf("jump: got %+v ok=%v", s, ok)
	}

	calm := make([]float64, 40)
	for i := range calm {
		calm[i] = 10 + 0.01*float64(i%3)
	}
	if s, _ := zscore(bars(calm...), Defaults()); s.Severity != Calm {
		t.Fatalf("calm: got %+v", s)
	}

	if _, ok := zscore(bars(10), Defaults()); ok {
		t.Fatal("want ok=false for <3 closes")
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/signals/ -v` → FAIL (package missing).

- [ ] **Step 3: Implement types** — `internal/signals/signals.go`

```go
// Package signals computes deterministic price/volume anomaly signals. Each
// signal is a pure function over a bar series; severity is the signal's own
// judgement against tunable thresholds.
package signals

import "math"

// Severity ranks how much attention a signal demands.
type Severity int

const (
	Calm Severity = iota
	Watch
	Look
)

func (s Severity) String() string {
	switch s {
	case Look:
		return "LOOK"
	case Watch:
		return "watch"
	default:
		return "calm"
	}
}

// Signal is one indicator's reading for a ticker.
type Signal struct {
	Name     string
	Value    float64
	Severity Severity
	Reason   string
}

// Thresholds are the tunable cutoffs for every signal.
type Thresholds struct {
	ZWatch, ZLook                                  float64
	RSIWatchHigh, RSILookHigh, RSIWatchLow, RSILookLow float64
	DrawWatch, DrawLook                            float64 // percent, negative
	Prox52Band                                     float64 // percent
	VolWatch, VolLook                              float64 // ×avg
}

// Defaults are the built-in thresholds used when config omits a value.
func Defaults() Thresholds {
	return Thresholds{
		ZWatch: 2, ZLook: 3,
		RSIWatchHigh: 70, RSILookHigh: 80, RSIWatchLow: 30, RSILookLow: 20,
		DrawWatch: -10, DrawLook: -20,
		Prox52Band: 3,
		VolWatch: 2, VolLook: 3,
	}
}

func closes(bars []priceBars) {} // placeholder removed in step 3b

func mean(xs []float64) float64 {
	s := 0.0
	for _, x := range xs {
		s += x
	}
	return s / float64(len(xs))
}

func stddev(xs []float64, mu float64) float64 {
	s := 0.0
	for _, x := range xs {
		s += (x - mu) * (x - mu)
	}
	return math.Sqrt(s / float64(len(xs)))
}
```
(Delete the stray `closes`/`priceBars` placeholder line — it is shown only to flag that the closes helper lives in `zscore.go` next.)

- [ ] **Step 3b: Implement zscore** — `internal/signals/zscore.go`

```go
package signals

import (
	"fmt"
	"math"

	"github.com/carvalhosauro/watchman/internal/prices"
)

// closeSeries extracts closes oldest→newest.
func closeSeries(bars []prices.Bar) []float64 {
	out := make([]float64, len(bars))
	for i, b := range bars {
		out[i] = b.Close
	}
	return out
}

// zscore scores how unusual the latest daily return is vs the prior returns.
func zscore(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < 3 {
		return Signal{}, false
	}
	returns := make([]float64, 0, len(cs)-1)
	for i := 1; i < len(cs); i++ {
		returns = append(returns, (cs[i]-cs[i-1])/cs[i-1]*100)
	}
	latest := returns[len(returns)-1]
	prior := returns[:len(returns)-1]
	mu := mean(prior)
	sigma := stddev(prior, mu)
	z := 0.0
	switch {
	case sigma != 0:
		z = (latest - mu) / sigma
	case latest != mu:
		z = math.Copysign(math.Inf(1), latest-mu)
	}
	sev := Calm
	switch {
	case math.Abs(z) >= t.ZLook:
		sev = Look
	case math.Abs(z) >= t.ZWatch:
		sev = Watch
	}
	return Signal{Name: "zscore", Value: z, Severity: sev,
		Reason: fmt.Sprintf("%.1f%% (%.1fσ)", latest, z)}, true
}
```
Remove the placeholder `closes`/`priceBars` line from `signals.go` now.

- [ ] **Step 4: Run** — `go test ./internal/signals/ -v` → PASS.
- [ ] **Step 5: Commit** — `git add internal/signals && git commit -m "feat(signals): severity types, thresholds, zscore"`

**✅ Done when:** `go test ./internal/signals/` passes; zscore returns Look on a flat-then-jump series, Calm on a quiet one, `ok=false` for <3 closes.

---

### Task 3: `rsi` signal (Wilder 14)

**Files:**
- Create: `internal/signals/rsi.go`
- Modify: `internal/signals/signals_test.go`

**Interfaces:**
- Produces: `func rsi(bars []prices.Bar, t Thresholds) (Signal, bool)`.

- [ ] **Step 1: Failing test** (append)

```go
func TestRSI(t *testing.T) {
	up := make([]float64, 20) // monotonic rise → RSI ~100 → Look
	for i := range up {
		up[i] = 10 + float64(i)
	}
	if s, ok := rsi(bars(up...), Defaults()); !ok || s.Severity != Look || s.Value <= 80 {
		t.Fatalf("up: got %+v ok=%v", s, ok)
	}
	if _, ok := rsi(bars(10, 11), Defaults()); ok {
		t.Fatal("want ok=false for <15 closes")
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/signals/ -run TestRSI` → FAIL.

- [ ] **Step 3: Implement** — `internal/signals/rsi.go`

```go
package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

const rsiPeriod = 14

// rsi is the Wilder Relative Strength Index over the last rsiPeriod deltas.
func rsi(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < rsiPeriod+1 {
		return Signal{}, false
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
	r := 100.0
	if avgLoss != 0 {
		r = 100 - 100/(1+avgGain/avgLoss)
	}
	sev := Calm
	switch {
	case r >= t.RSILookHigh || r <= t.RSILookLow:
		sev = Look
	case r >= t.RSIWatchHigh || r <= t.RSIWatchLow:
		sev = Watch
	}
	return Signal{Name: "rsi", Value: r, Severity: sev,
		Reason: fmt.Sprintf("RSI %.0f", r)}, true
}
```

- [ ] **Step 4: Run** — `go test ./internal/signals/ -run TestRSI` → PASS.
- [ ] **Step 5: Commit** — `git add internal/signals && git commit -m "feat(signals): Wilder RSI(14)"`

**✅ Done when:** monotonic rise → RSI ≥80 → Look; `<15` closes → `ok=false`.

---

### Task 4: `drawdown` signal

**Files:**
- Create: `internal/signals/drawdown.go`
- Modify: `internal/signals/signals_test.go`

**Interfaces:**
- Produces: `func drawdown(bars []prices.Bar, t Thresholds) (Signal, bool)`.

- [ ] **Step 1: Failing test** (append)

```go
func TestDrawdown(t *testing.T) {
	// peak 20, last 15 → -25% → Look
	if s, ok := drawdown(bars(10, 20, 18, 15), Defaults()); !ok || s.Severity != Look {
		t.Fatalf("deep: got %+v ok=%v", s, ok)
	}
	// rising → 0 drawdown → Calm
	if s, _ := drawdown(bars(10, 11, 12), Defaults()); s.Severity != Calm {
		t.Fatalf("rising: got %+v", s)
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/signals/ -run TestDrawdown` → FAIL.

- [ ] **Step 3: Implement** — `internal/signals/drawdown.go`

```go
package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

// drawdown is the percent decline of the latest close from the trailing peak.
func drawdown(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < 2 {
		return Signal{}, false
	}
	peak := cs[0]
	for _, c := range cs {
		if c > peak {
			peak = c
		}
	}
	dd := 0.0
	if peak != 0 {
		dd = (cs[len(cs)-1] - peak) / peak * 100
	}
	sev := Calm
	switch {
	case dd <= t.DrawLook:
		sev = Look
	case dd <= t.DrawWatch:
		sev = Watch
	}
	return Signal{Name: "drawdown", Value: dd, Severity: sev,
		Reason: fmt.Sprintf("%.0f%% vs peak", dd)}, true
}
```

- [ ] **Step 4: Run** — `go test ./internal/signals/ -run TestDrawdown` → PASS.
- [ ] **Step 5: Commit** — `git add internal/signals && git commit -m "feat(signals): drawdown from peak"`

**✅ Done when:** −25% from peak → Look; rising series → Calm.

---

### Task 5: `prox52w` signal

**Files:**
- Create: `internal/signals/prox52w.go`
- Modify: `internal/signals/signals_test.go`

**Interfaces:**
- Produces: `func prox52w(bars []prices.Bar, t Thresholds) (Signal, bool)`.

- [ ] **Step 1: Failing test** (append)

```go
func TestProx52w(t *testing.T) {
	s := make([]float64, 200)
	for i := range s {
		s[i] = 10 + float64(i)*0.1 // ends at the high → Look (new high)
	}
	if r, ok := prox52w(bars(s...), Defaults()); !ok || r.Severity != Look {
		t.Fatalf("high: got %+v ok=%v", r, ok)
	}
	mid := make([]float64, 200) // last far from extremes → Calm
	for i := range mid {
		mid[i] = 10 + float64(i)*0.1
	}
	mid[len(mid)-1] = 20 // well below the 29.9 high, above the 10 low
	if r, _ := prox52w(bars(mid...), Defaults()); r.Severity != Calm {
		t.Fatalf("mid: got %+v", r)
	}
	if _, ok := prox52w(bars(10, 11), Defaults()); ok {
		t.Fatal("want ok=false for <200 closes")
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/signals/ -run TestProx52w` → FAIL.

- [ ] **Step 3: Implement** — `internal/signals/prox52w.go`

```go
package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

const prox52Min = 200

// prox52w scores how close the latest close is to its 1-year high/low.
func prox52w(bars []prices.Bar, t Thresholds) (Signal, bool) {
	cs := closeSeries(bars)
	if len(cs) < prox52Min {
		return Signal{}, false
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
	last := cs[len(cs)-1]
	toHigh, toLow := 100.0, 100.0
	if hi != 0 {
		toHigh = (hi - last) / hi * 100
	}
	if lo != 0 {
		toLow = (last - lo) / lo * 100
	}
	near := toHigh
	label := "to 52w high"
	if toLow < toHigh {
		near, label = toLow, "to 52w low"
	}
	sev := Calm
	switch {
	case last >= hi || last <= lo:
		sev = Look
	case near <= t.Prox52Band:
		sev = Watch
	}
	return Signal{Name: "prox52w", Value: near, Severity: sev,
		Reason: fmt.Sprintf("%.1f%% %s", near, label)}, true
}
```

- [ ] **Step 4: Run** — `go test ./internal/signals/ -run TestProx52w` → PASS.
- [ ] **Step 5: Commit** — `git add internal/signals && git commit -m "feat(signals): 52-week proximity"`

**✅ Done when:** ending at the high → Look; mid-range → Calm; `<200` closes → `ok=false`.

---

### Task 6: `volume` signal + `Evaluate`

**Files:**
- Create: `internal/signals/volume.go`
- Modify: `internal/signals/signals.go` (add `Evaluate`)
- Modify: `internal/signals/signals_test.go`

**Interfaces:**
- Produces: `func volume(bars []prices.Bar, t Thresholds) (Signal, bool)`; `func Evaluate(bars []prices.Bar, t Thresholds) []Signal`.

- [ ] **Step 1: Failing test** (append)

```go
func volBars(vols ...float64) []prices.Bar {
	out := make([]prices.Bar, len(vols))
	for i, v := range vols {
		out[i] = prices.Bar{Close: 10, Volume: v}
	}
	return out
}

func TestVolume(t *testing.T) {
	v := make([]float64, 21)
	for i := range v {
		v[i] = 100
	}
	v[len(v)-1] = 400 // 4× the 100-avg → Look
	if s, ok := volume(volBars(v...), Defaults()); !ok || s.Severity != Look {
		t.Fatalf("spike: got %+v ok=%v", s, ok)
	}
	if _, ok := volume(volBars(100, 100), Defaults()); ok {
		t.Fatal("want ok=false for <21 bars")
	}
}

func TestEvaluate(t *testing.T) {
	flat := make([]float64, 30)
	for i := range flat {
		flat[i] = 10
	}
	jump := append(append([]float64{}, flat...), 13)
	got := Evaluate(bars(jump...), Defaults())
	if len(got) == 0 {
		t.Fatal("Evaluate returned nothing")
	}
	// zscore must be present even though prox52w/volume can't compute
	var hasZ bool
	for _, s := range got {
		if s.Name == "zscore" {
			hasZ = true
		}
	}
	if !hasZ {
		t.Fatalf("zscore missing: %+v", got)
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/signals/ -run 'TestVolume|TestEvaluate'` → FAIL.

- [ ] **Step 3: Implement volume** — `internal/signals/volume.go`

```go
package signals

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/prices"
)

const volWindow = 20

// volume scores the latest volume against its trailing-window average.
func volume(bars []prices.Bar, t Thresholds) (Signal, bool) {
	if len(bars) < volWindow+1 {
		return Signal{}, false
	}
	window := bars[len(bars)-volWindow-1 : len(bars)-1]
	var sum float64
	for _, b := range window {
		sum += b.Volume
	}
	avg := sum / float64(volWindow)
	if avg == 0 {
		return Signal{}, false
	}
	ratio := bars[len(bars)-1].Volume / avg
	sev := Calm
	switch {
	case ratio >= t.VolLook:
		sev = Look
	case ratio >= t.VolWatch:
		sev = Watch
	}
	return Signal{Name: "volume", Value: ratio, Severity: sev,
		Reason: fmt.Sprintf("vol %.1f×", ratio)}, true
}
```

- [ ] **Step 3b: Add Evaluate** — append to `internal/signals/signals.go`

```go
// Evaluate runs every signal over bars and returns those that could be
// computed, including Calm ones (presentation decides what to surface).
func Evaluate(bars []prices.Bar, t Thresholds) []Signal {
	fns := []func([]prices.Bar, Thresholds) (Signal, bool){
		zscore, rsi, drawdown, prox52w, volume,
	}
	out := make([]Signal, 0, len(fns))
	for _, fn := range fns {
		if s, ok := fn(bars, t); ok {
			out = append(out, s)
		}
	}
	return out
}
```
Add `"github.com/carvalhosauro/watchman/internal/prices"` to `signals.go` imports.

- [ ] **Step 4: Run** — `go test ./internal/signals/ -v` → PASS.
- [ ] **Step 5: Commit** — `git add internal/signals && git commit -m "feat(signals): volume spike + Evaluate"`

**✅ Done when:** 4× volume spike → Look; `Evaluate` returns all computable signals (zscore present on a 31-bar series).

---

### Task 7: `config` — TOML thresholds with defaults

**Files:**
- Create: `internal/config/config.go`
- Create: `internal/config/config_test.go`
- Modify: `go.mod`, `go.sum` (add `github.com/BurntSushi/toml`)

**Interfaces:**
- Consumes: `signals.Thresholds`, `signals.Defaults()`.
- Produces: `func Path() string`; `func Load() (signals.Thresholds, error)`.

- [ ] **Step 1: Add dep** — `go get github.com/BurntSushi/toml@latest` then `go mod tidy`.

- [ ] **Step 2: Failing test** — `internal/config/config_test.go`

```go
package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDefaultsWhenMissing(t *testing.T) {
	t.Setenv("WATCHMAN_CONFIG", filepath.Join(t.TempDir(), "nope.toml"))
	th, err := Load()
	if err != nil || th.ZLook != 3 || th.VolWatch != 2 {
		t.Fatalf("defaults not applied: %+v err=%v", th, err)
	}
}

func TestLoadOverride(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.toml")
	os.WriteFile(p, []byte("[zscore]\nlook = 4.0\n"), 0o644)
	t.Setenv("WATCHMAN_CONFIG", p)
	th, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if th.ZLook != 4.0 {
		t.Fatalf("override ZLook=%v", th.ZLook)
	}
	if th.ZWatch != 2.0 { // untouched key keeps default
		t.Fatalf("default ZWatch lost: %v", th.ZWatch)
	}
}
```

- [ ] **Step 3: Run, expect FAIL** — `go test ./internal/config/` → FAIL (package missing).

- [ ] **Step 4: Implement** — `internal/config/config.go`

```go
// Package config loads tunable signal thresholds from a TOML file, falling
// back to signals.Defaults() for any missing value.
package config

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
	"github.com/carvalhosauro/watchman/internal/signals"
)

// Path is the config file location; WATCHMAN_CONFIG overrides it.
func Path() string {
	if p := os.Getenv("WATCHMAN_CONFIG"); p != "" {
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "watchman", "config.toml")
}

// file mirrors the TOML layout; pointers tell "absent" from "zero".
type file struct {
	Zscore   struct{ Watch, Look *float64 }
	RSI      struct{ WatchHigh, LookHigh, WatchLow, LookLow *float64 } `toml:"rsi"`
	Drawdown struct{ Watch, Look *float64 }
	Prox52w  struct{ Band *float64 } `toml:"prox52w"`
	Volume   struct{ Watch, Look *float64 }
}

// Load reads the config file and fills missing keys from defaults.
func Load() (signals.Thresholds, error) {
	t := signals.Defaults()
	var f file
	if _, err := toml.DecodeFile(Path(), &f); err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return t, nil // no file → all defaults
		}
		return t, err
	}
	set := func(dst *float64, src *float64) {
		if src != nil {
			*dst = *src
		}
	}
	set(&t.ZWatch, f.Zscore.Watch)
	set(&t.ZLook, f.Zscore.Look)
	set(&t.RSIWatchHigh, f.RSI.WatchHigh)
	set(&t.RSILookHigh, f.RSI.LookHigh)
	set(&t.RSIWatchLow, f.RSI.WatchLow)
	set(&t.RSILookLow, f.RSI.LookLow)
	set(&t.DrawWatch, f.Drawdown.Watch)
	set(&t.DrawLook, f.Drawdown.Look)
	set(&t.Prox52Band, f.Prox52w.Band)
	set(&t.VolWatch, f.Volume.Watch)
	set(&t.VolLook, f.Volume.Look)
	return t, nil
}
```

- [ ] **Step 5: Run** — `go test ./internal/config/ -v` → PASS.
- [ ] **Step 6: Commit** — `git add internal/config go.mod go.sum && git commit -m "feat(config): TOML thresholds with defaults"`

**✅ Done when:** missing file → defaults; a partial TOML overrides only its keys, others keep defaults; `WATCHMAN_CONFIG` honored.

---

### Task 8: `verdict` — severity + count from signals

**Files:**
- Modify: `internal/verdict/verdict.go` (replace)
- Modify: `internal/verdict/verdict_test.go` (replace)

**Interfaces:**
- Consumes: `signals.Signal`, `signals.Severity`.
- Produces: `type Decision struct { Severity signals.Severity; Count int; Reason string }`; `func Decide(sigs []signals.Signal) Decision`.

- [ ] **Step 1: Replace the test** — `internal/verdict/verdict_test.go`

```go
package verdict

import (
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/signals"
)

func TestDecide(t *testing.T) {
	in := []signals.Signal{
		{Name: "zscore", Severity: signals.Look, Reason: "-6.1% (2.8σ)"},
		{Name: "rsi", Severity: signals.Watch, Reason: "RSI 72"},
		{Name: "volume", Severity: signals.Calm, Reason: "vol 1.1×"},
	}
	d := Decide(in)
	if d.Severity != signals.Look {
		t.Fatalf("severity=%v", d.Severity)
	}
	if d.Count != 2 { // Look + Watch fired; Calm doesn't count
		t.Fatalf("count=%d", d.Count)
	}
	if !strings.Contains(d.Reason, "2.8σ") || strings.Contains(d.Reason, "1.1×") {
		t.Fatalf("reason=%q", d.Reason)
	}
}

func TestDecideCalm(t *testing.T) {
	d := Decide([]signals.Signal{{Name: "zscore", Severity: signals.Calm}})
	if d.Severity != signals.Calm || d.Count != 0 {
		t.Fatalf("got %+v", d)
	}
	if d.Reason != "quiet" {
		t.Fatalf("reason=%q", d.Reason)
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/verdict/` → FAIL.

- [ ] **Step 3: Replace impl** — `internal/verdict/verdict.go`

```go
// Package verdict reduces a set of signals to one severity + count, with a
// human-readable reason naming the signals that fired.
package verdict

import (
	"strings"

	"github.com/carvalhosauro/watchman/internal/signals"
)

// Decision is the per-ticker call.
type Decision struct {
	Severity signals.Severity
	Count    int
	Reason   string
}

// Decide takes the max severity across signals; Count is how many fired
// (≥ Watch); Reason joins the fired signals' reasons (or "quiet").
func Decide(sigs []signals.Signal) Decision {
	d := Decision{Severity: signals.Calm}
	reasons := make([]string, 0, len(sigs))
	for _, s := range sigs {
		if s.Severity >= signals.Watch {
			d.Count++
			reasons = append(reasons, s.Reason)
			if s.Severity > d.Severity {
				d.Severity = s.Severity
			}
		}
	}
	if len(reasons) == 0 {
		d.Reason = "quiet"
	} else {
		d.Reason = strings.Join(reasons, " · ")
	}
	return d
}
```

- [ ] **Step 4: Run** — `go test ./internal/verdict/ -v` → PASS.
- [ ] **Step 5: Commit** — `git add internal/verdict && git commit -m "feat(verdict): severity + count from signals"`

**✅ Done when:** max severity wins; Count = fired (≥Watch) signals; Reason joins fired reasons, "quiet" when none.

---

### Task 9: `glance` rewrite — rank, render, classify failures

**Files:**
- Modify: `internal/glance/glance.go` (replace)
- Modify: `internal/glance/glance_test.go` (replace)
- Modify: `cmd/run.go` (update `glance.Run` call + load config)

**Interfaces:**
- Consumes: `prices.History`/`prices.ErrNoData`/`prices.Bar`, `signals.Evaluate`/`signals.Thresholds`/`signals.Signal`, `verdict.Decide`.
- Produces: `type Row struct { Ticker string; Sev signals.Severity; Count int; Reason string; Fail string; Sigs []signals.Signal; mag float64 }`; `func BuildRow(ticker string, bars []prices.Bar, fetchErr error, t signals.Thresholds) Row`; `func Run(tickers []string, t signals.Thresholds) []Row`; `func Format(rows []Row, detail bool) string`.

- [ ] **Step 1: Replace the test** — `internal/glance/glance_test.go`

```go
package glance

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/prices"
	"github.com/carvalhosauro/watchman/internal/signals"
)

func barsOf(closes []float64, vol float64) []prices.Bar {
	out := make([]prices.Bar, len(closes))
	for i, c := range closes {
		out[i] = prices.Bar{Close: c, Volume: vol}
	}
	return out
}

func TestBuildRowAbnormal(t *testing.T) {
	cl := make([]float64, 30)
	for i := range cl {
		cl[i] = 10
	}
	cl = append(cl, 13)
	r := BuildRow("PETR4", barsOf(cl, 1000), nil, signals.Defaults())
	if r.Sev != signals.Look || r.Count < 1 {
		t.Fatalf("got %+v", r)
	}
}

func TestBuildRowNoData(t *testing.T) {
	r := BuildRow("XPTO3", nil, prices.ErrNoData, signals.Defaults())
	if r.Fail != "No data" {
		t.Fatalf("got %+v", r)
	}
}

func TestBuildRowAPIError(t *testing.T) {
	r := BuildRow("ZZZZ3", nil, errors.New("http 500"), signals.Defaults())
	if r.Fail != "API error" {
		t.Fatalf("got %+v", r)
	}
}

func TestFormatSortsWorstFirst(t *testing.T) {
	rows := []Row{
		{Ticker: "CALM1", Sev: signals.Calm, Reason: "quiet"},
		{Ticker: "LOOKER", Sev: signals.Look, Count: 2, Reason: "x"},
		{Ticker: "WATCHER", Sev: signals.Watch, Count: 1, Reason: "y"},
	}
	out := Format(rows, false)
	if strings.Index(out, "LOOKER") > strings.Index(out, "WATCHER") ||
		strings.Index(out, "WATCHER") > strings.Index(out, "CALM1") {
		t.Fatalf("bad order:\n%s", out)
	}
}

func TestRunFlow(t *testing.T) {
	orig := prices.BaseURL
	t.Cleanup(func() { prices.BaseURL = orig })
	cl := make([]string, 0)
	_ = cl
	body := `{"chart":{"error":null,"result":[{"timestamp":[1,2,3],"indicators":{"quote":[{"close":[10,10,13],"volume":[1,1,1]}]}}]}}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(body))
	}))
	defer srv.Close()
	prices.BaseURL = srv.URL
	rows := Run([]string{"PETR4"}, signals.Defaults())
	if len(rows) != 1 {
		t.Fatalf("got %+v", rows)
	}
}
```

- [ ] **Step 2: Run, expect FAIL** — `go test ./internal/glance/` → FAIL.

- [ ] **Step 3: Replace impl** — `internal/glance/glance.go`

```go
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
```

- [ ] **Step 4: Update `cmd/run.go`** so it compiles (full flags land in Task 10)

```go
package cmd

import (
	"fmt"
	"time"

	"github.com/carvalhosauro/watchman/internal/config"
	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(&cobra.Command{
		Use:   "run",
		Short: "fetch and show the noise/look glance",
		RunE: func(cmd *cobra.Command, _ []string) error {
			out := cmd.OutOrStdout()
			ts, err := wallet.List(wallet.Path())
			if err != nil {
				return err
			}
			if len(ts) == 0 {
				_, _ = fmt.Fprintln(out, "No tickers. Add with: wm wallet add PETR4")
				return nil
			}
			th, err := config.Load()
			if err != nil {
				return err
			}
			_, _ = fmt.Fprintf(out, "watchman — %s\n", time.Now().UTC().Format("2006-01-02"))
			_, _ = fmt.Fprint(out, glance.Format(glance.Run(ts, th), false))
			return nil
		},
	})
}
```

- [ ] **Step 5: Run** — `go test ./internal/glance/ ./cmd/ -v` → PASS. Then `go build ./cmd/wm` (still red on anomaly/news imports — fixed in Task 10).

- [ ] **Step 6: Commit** — `git add internal/glance cmd/run.go && git commit -m "feat(glance): rank + render multi-signal verdict, classify failures"`

**✅ Done when:** `BuildRow` yields Look on the jump series, "No data" on `ErrNoData`, "API error" otherwise; `Format` sorts worst-first; `glance`/`cmd` tests pass.

---

### Task 10: `cmd/run` flags, delete `news`+`anomaly`, green tree

**Files:**
- Modify: `cmd/run.go` (flags + args)
- Modify: `cmd/run_test.go`
- Delete: `internal/news/` (whole dir), `internal/anomaly/` (whole dir)
- Modify: `cmd/wm/mock_test.go` (drop news; 1y+volume fixture), `cmd/wm/testdata/script/run.txtar`, `cmd/wm/live_test.go`

**Interfaces:**
- Consumes: `glance.Run`, `glance.Format`, `config.Load`, `wallet.List`.

- [ ] **Step 1: Delete dead packages**

```bash
git rm -r internal/news internal/anomaly
```

- [ ] **Step 2: Replace `cmd/run.go`** with flags + optional ticker args

```go
package cmd

import (
	"fmt"
	"time"

	"github.com/carvalhosauro/watchman/internal/config"
	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/signals"
	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	var detail, lookOnly bool
	cmd := &cobra.Command{
		Use:   "run [TICKER...]",
		Short: "fetch and show the noise/look glance",
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
			th, err := config.Load()
			if err != nil {
				return err
			}
			rows := glance.Run(tickers, th)
			if lookOnly {
				rows = glance.OnlyAttention(rows)
			}
			_, _ = fmt.Fprintf(out, "watchman — %s\n", time.Now().UTC().Format("2006-01-02"))
			_, _ = fmt.Fprint(out, glance.Format(rows, detail))
			return nil
		},
	}
	cmd.Flags().BoolVar(&detail, "detail", false, "show every signal per ticker, calm or not")
	cmd.Flags().BoolVar(&lookOnly, "look", false, "show only watch/LOOK rows")
	rootCmd.AddCommand(cmd)
	_ = signals.Calm // keep import if unused after edits; remove if linter flags
}
```
Remove the stray `_ = signals.Calm` line if `signals` is otherwise unused (it is — delete the import and the line).

- [ ] **Step 3: Add `OnlyAttention` to glance** — append to `internal/glance/glance.go`

```go
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
```

- [ ] **Step 4: Rewrite `cmd/wm/mock_test.go`** — drop news routing; serve 1-year close+volume; PETR4 abnormal, others calm, XPTO3 error

```go
package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func chart(closes []float64) []byte {
	ts := make([]int64, len(closes))
	vol := make([]float64, len(closes))
	for i := range closes {
		ts[i] = int64(i) * 86400
		vol[i] = 1000
	}
	var r struct {
		Chart struct {
			Error  any `json:"error"`
			Result []struct {
				Timestamp  []int64 `json:"timestamp"`
				Indicators struct {
					Quote []struct {
						Close  []float64 `json:"close"`
						Volume []float64 `json:"volume"`
					} `json:"quote"`
				} `json:"indicators"`
			} `json:"result"`
		} `json:"chart"`
	}
	res := struct {
		Timestamp  []int64 `json:"timestamp"`
		Indicators struct {
			Quote []struct {
				Close  []float64 `json:"close"`
				Volume []float64 `json:"volume"`
			} `json:"quote"`
		} `json:"indicators"`
	}{Timestamp: ts}
	res.Indicators.Quote = append(res.Indicators.Quote, struct {
		Close  []float64 `json:"close"`
		Volume []float64 `json:"volume"`
	}{Close: closes, Volume: vol})
	r.Chart.Result = append(r.Chart.Result, res)
	b, _ := json.Marshal(r)
	return b
}

func abnormalSeries() []float64 {
	s := make([]float64, 30)
	for i := range s {
		s[i] = 10
	}
	return append(s, 13)
}

func calmSeries() []float64 {
	s := make([]float64, 40)
	for i := range s {
		s[i] = 10 + 0.01*float64(i%3)
	}
	return s
}

func newMockServer(t *testing.T) *httptest.Server {
	t.Helper()
	errPayload := []byte(`{"chart":{"error":"Not Found","result":null}}`)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "PETR4"):
			_, _ = w.Write(chart(abnormalSeries()))
		case strings.Contains(r.URL.Path, "XPTO3"):
			_, _ = w.Write(errPayload)
		default:
			_, _ = w.Write(chart(calmSeries()))
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}
```
(Delete the old `TestMockDrivesGlance` that referenced `glance.Run(...)` with the old signature — replace its body to call `glance.Run([]string{...}, signals.Defaults())` and assert `Sev`/`Fail`. Import `internal/glance` + `internal/prices` + `internal/signals`.)

- [ ] **Step 5: Update `cmd/wm/script_test.go` Setup** — drop the `WATCHMAN_NEWS_URL` line (news is gone); keep `WATCHMAN_PRICES_URL` + `WATCHMAN_WALLET`.

- [ ] **Step 6: Update `run.txtar`** — `cmd/wm/testdata/script/run.txtar` (wallet `PETR4`, `MXRF11`, `XPTO3`; assert ranking + failure row)

```
cp wallet_seed wallet
wm run
stdout 'watchman'
stdout 'LOOK.*PETR4'
stdout 'ignore|calm MXRF11|MXRF11'
stdout 'XPTO3.*No data'

# detail shows every signal incl calm
wm run PETR4 --detail
stdout 'PETR4'

-- wallet_seed --
PETR4
MXRF11
XPTO3
```

- [ ] **Step 7: Update `cmd/wm/live_test.go`** — replace `glance.Format(glance.Run(tickers))` with `glance.Format(glance.Run(tickers, signals.Defaults()), false)`; add the `signals` import. (Tolerant assertions unchanged.)

- [ ] **Step 8: Tidy + full gate**

```bash
go mod tidy
gofmt -w .
go test -race ./...
golangci-lint run
bash scripts/coverage.sh 80
go build -o bin/wm ./cmd/wm
```
Expected: all green, coverage ≥80, build ok, no references to `internal/news` or `internal/anomaly`.

- [ ] **Step 9: Live milestone**

```bash
WATCHMAN_WALLET=$(mktemp) ; printf 'PETR4\nITUB4\n' >| "$WATCHMAN_WALLET" ; ./bin/wm run ; ./bin/wm run --detail PETR4
```
Expected: dated header, ranked rows worst-first; `--detail PETR4` lists every signal.

- [ ] **Step 10: Commit** — `git add -A && git commit -m "feat(run): --detail/--look/ticker args; drop news+anomaly; green tree"`

**✅ Done when:** `internal/news`+`internal/anomaly` gone; `go test -race ./...` green; coverage ≥80; `golangci-lint` 0 issues; `wm run`, `wm run --detail`, `wm run --look`, `wm run PETR4` all work; live run ranks holdings.

---

### Task 11: Docs, README, ROADMAP, config example

**Files:**
- Modify: `README.md`, `ROADMAP.md`, `CHANGELOG.md`
- Create: `docs/config.example.toml`

- [ ] **Step 1: README** — update "The rule" → describe the 5 signals + severity/count; document `wm run`, `--detail`, `--look`, `wm run TICKER`, and the config file (`~/.config/watchman/config.toml`, `WATCHMAN_CONFIG`). Update "What it doesn't do" (remove news; it's gone now, not "roadmap").

- [ ] **Step 2: Config example** — `docs/config.example.toml` with the full default block (the TOML from the spec) and a one-line comment per key.

- [ ] **Step 3: ROADMAP** — set v2.1 = "anomaly engine (shipped)"; remove the news-fix item; note the abandoned `fix/news-feed` branch.

- [ ] **Step 4: Changelog + gate**

```bash
make ci
git cliff -o CHANGELOG.md
git add README.md ROADMAP.md CHANGELOG.md docs/config.example.toml && git commit -m "docs: anomaly engine, config, roadmap for v2.1"
```

**✅ Done when:** README documents the engine + config + flags; `docs/config.example.toml` present; ROADMAP reflects the pivot; `make ci` green.

---

## Self-Review

- **Spec coverage:** prices→Bar (T1) · 5 signals (T2–T6) · Evaluate (T6) · config/TOML (T7) · verdict severity+count (T8) · glance rank+render+typed errors (T9) · flags/detail/look/args + deletions (T10) · docs/config/roadmap (T11). News+anomaly deletion (T10). All spec sections mapped.
- **Placeholder note:** T2 Step 3 deliberately shows a `closes`/`priceBars` stray line *with an explicit instruction to delete it* — it flags that the helper moves to `zscore.go`; not a real placeholder. Every code step ships real code.
- **Type consistency:** `signals.Thresholds`/`Defaults()` (T2) consumed by config (T7), signals funcs (T2–T6), glance (T9). `signals.Signal`/`Severity` flow T2→T8→T9. `prices.Bar`/`ErrNoData` (T1) → signals/glance. `glance.Run(tickers, t)` + `Format(rows, detail)` + `OnlyAttention` consistent T9↔T10. `config.Load() (signals.Thresholds, error)` used in cmd (T9/T10).
- **Green-tree caveat is explicit:** T1 notes the tree is red until T10; each task runs package-scoped tests; T10 Step 8 restores `go test -race ./...` + build + coverage.

## Execution Handoff

Plan saved to `docs/superpowers/plans/2026-06-21-anomaly-engine.md`.
