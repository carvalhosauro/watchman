package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/news"
	"github.com/carvalhosauro/watchman/internal/prices"
)

// pricesPayload builds a Yahoo chart response carrying the given closes.
func pricesPayload(closes []float64) []byte {
	type quote struct {
		Close []float64 `json:"close"`
	}
	type result struct {
		Indicators struct {
			Quote []quote `json:"quote"`
		} `json:"indicators"`
	}
	var r struct {
		Chart struct {
			Error  any      `json:"error"`
			Result []result `json:"result"`
		} `json:"chart"`
	}
	res := result{}
	res.Indicators.Quote = []quote{{Close: closes}}
	r.Chart.Result = []result{res}
	b, _ := json.Marshal(r)
	return b
}

func calmCloses() []float64 {
	out := make([]float64, 0, 40)
	for range 20 {
		out = append(out, 10.0, 10.1) // |z| ~ 1 -> not abnormal
	}
	return out
}

func abnormalCloses() []float64 {
	out := make([]float64, 30) // 30 flat days …
	for i := range out {
		out[i] = 10.0
	}
	return append(out, 13.0) // … then a +30% jump
}

// newMockServer returns a deterministic stand-in for Yahoo (prices) and the CVM
// feed (news), routed by request path. It mirrors the fixtures the e2e suite used:
//
//	PETR4  -> flat 30d then +30% -> abnormal -> LOOK
//	MXRF11 -> gentle series      -> calm      -> ignore
//	XPTO3  -> Yahoo error payload -> no price data -> ignore
//	others -> calm series (price-only)
//	news   -> one "VALE3 - Fato Relevante" item dated today (UTC) -> VALE3 fresh
func newMockServer(t *testing.T) *httptest.Server {
	t.Helper()
	errPayload := []byte(`{"chart":{"error":"Not Found","result":null}}`)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "news"):
			today := time.Now().UTC().Format("Mon, 02 Jan 2006 15:04:05 GMT")
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte("<rss><channel>" +
				"<item><title>VALE3 - Fato Relevante sobre projeto</title><pubDate>" + today + "</pubDate></item>" +
				"</channel></rss>"))
		case strings.Contains(r.URL.Path, "PETR4"):
			_, _ = w.Write(pricesPayload(abnormalCloses()))
		case strings.Contains(r.URL.Path, "XPTO3"):
			_, _ = w.Write(errPayload)
		default:
			_, _ = w.Write(pricesPayload(calmCloses()))
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

// TestMockDrivesGlance pins the seams at the mock and asserts the full verdict
// matrix in-process (no subprocess, no real network).
func TestMockDrivesGlance(t *testing.T) {
	srv := newMockServer(t)
	op, on := prices.BaseURL, news.FeedURL
	t.Cleanup(func() { prices.BaseURL, news.FeedURL = op, on })
	prices.BaseURL = srv.URL + "/prices"
	news.FeedURL = srv.URL + "/news"

	rows := glance.Run([]string{"PETR4", "MXRF11", "VALE3", "XPTO3"})
	want := map[string]struct {
		look   bool
		reason string
	}{
		"PETR4":  {true, "moved"},
		"MXRF11": {false, "quiet"},
		"VALE3":  {true, "news"},
		"XPTO3":  {false, "no price data"},
	}
	if len(rows) != 4 {
		t.Fatalf("got %d rows: %+v", len(rows), rows)
	}
	for _, row := range rows {
		w := want[row.Ticker]
		if row.Look != w.look || !strings.Contains(row.Reason, w.reason) {
			t.Errorf("%s = {Look:%v Reason:%q} want look=%v ~%q", row.Ticker, row.Look, row.Reason, w.look, w.reason)
		}
	}
}
