package glance

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/news"
	"github.com/carvalhosauro/watchman/internal/prices"
)

func TestBuildRowAbnormal(t *testing.T) {
	closes := make([]float64, 30)
	for i := range closes {
		closes[i] = 10.0
	}
	closes = append(closes, 13.0)
	if r := BuildRow("PETR4", closes, nil, false); !r.Look {
		t.Fatalf("want LOOK got %+v", r)
	}
}

func TestBuildRowFetchErr(t *testing.T) {
	r := BuildRow("XPTO3", nil, errors.New("x"), false)
	if r.Look || !strings.Contains(r.Reason, "no price") {
		t.Fatalf("got %+v", r)
	}
}

func TestFormat(t *testing.T) {
	out := Format([]Row{{"PETR4", true, "moved -6%"}, {"MXRF11", false, "quiet"}})
	if !strings.Contains(out, "LOOK") || !strings.Contains(out, "PETR4") || !strings.Contains(out, "MXRF11") {
		t.Fatalf("bad:\n%s", out)
	}
}

func TestRunFlow(t *testing.T) {
	origPrices, origFeed := prices.BaseURL, news.FeedURL
	t.Cleanup(func() { prices.BaseURL, news.FeedURL = origPrices, origFeed })

	body := `{"chart":{"error":null,"result":[{"indicators":{"quote":[{"close":[10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,13]}]}}]}}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte(body)) }))
	defer srv.Close()
	prices.BaseURL = srv.URL
	// keep news hermetic + fast: a closed server refuses at once → FetchItems nil → price-only path
	dead := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	dead.Close()
	news.FeedURL = dead.URL

	rows := Run([]string{"PETR4"})
	if len(rows) != 1 || !rows[0].Look {
		t.Fatalf("got %+v", rows)
	}
}
