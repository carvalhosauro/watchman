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

func TestFormatDetail(t *testing.T) {
	rows := []Row{{
		Ticker: "PETR4", Sev: signals.Look, Count: 1,
		Sigs: []signals.Signal{
			{Name: "zscore", Severity: signals.Look, Reason: "-6% (3σ)"},
			{Name: "rsi", Severity: signals.Calm, Reason: "RSI 55"},
		},
	}}
	out := Format(rows, true)
	if !strings.Contains(out, "-6% (3σ)") || !strings.Contains(out, "RSI 55") {
		t.Fatalf("detail should list every signal:\n%s", out)
	}
}

func TestFormatFailRow(t *testing.T) {
	out := Format([]Row{{Ticker: "XPTO3", Fail: "No data"}}, false)
	if !strings.Contains(out, "XPTO3") || !strings.Contains(out, "No data") {
		t.Fatalf("fail row:\n%s", out)
	}
}

func TestOnlyAttention(t *testing.T) {
	rows := []Row{
		{Ticker: "A", Sev: signals.Calm},
		{Ticker: "B", Sev: signals.Watch},
		{Ticker: "C", Fail: "API error"},
	}
	got := OnlyAttention(rows)
	if len(got) != 2 {
		t.Fatalf("want 2 (watch+fail), got %d: %+v", len(got), got)
	}
}

func TestRunFlow(t *testing.T) {
	orig := prices.BaseURL
	t.Cleanup(func() { prices.BaseURL = orig })
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
