package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/prices"
	"github.com/carvalhosauro/watchman/internal/scan"
	"github.com/carvalhosauro/watchman/internal/signals"
)

type quoteJSON struct {
	Close  []float64 `json:"close"`
	Volume []float64 `json:"volume"`
}

// chart builds a Yahoo chart payload for the given closes (volume = 1000 each).
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
					Quote []quoteJSON `json:"quote"`
				} `json:"indicators"`
			} `json:"result"`
		} `json:"chart"`
	}
	res := struct {
		Timestamp  []int64 `json:"timestamp"`
		Indicators struct {
			Quote []quoteJSON `json:"quote"`
		} `json:"indicators"`
	}{Timestamp: ts}
	res.Indicators.Quote = []quoteJSON{{Close: closes, Volume: vol}}
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

func scanSeries() []float64 {
	s := make([]float64, 210)
	for i := range s {
		s[i] = 100
	}
	s[209] = 40 // deep in range band
	return s
}

// newMockServer routes by ticker: PETR4 abnormal, SCAN1 scan series, XPTO3 error payload, others calm.
func newMockServer(t *testing.T) *httptest.Server {
	t.Helper()
	errPayload := []byte(`{"chart":{"error":"Not Found","result":null}}`)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "PETR4"):
			_, _ = w.Write(chart(abnormalSeries()))
		case strings.Contains(r.URL.Path, "SCAN1"):
			_, _ = w.Write(chart(scanSeries()))
		case strings.Contains(r.URL.Path, "XPTO3"):
			_, _ = w.Write(errPayload)
		default:
			_, _ = w.Write(chart(calmSeries()))
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

// TestMockDrivesGlance exercises glance.Run end-to-end against the mock.
func TestMockDrivesGlance(t *testing.T) {
	srv := newMockServer(t)
	orig := prices.BaseURL
	t.Cleanup(func() { prices.BaseURL = orig })
	prices.BaseURL = srv.URL + "/prices"

	rows := glance.Run([]string{"PETR4", "MXRF11", "XPTO3"}, signals.Defaults())
	got := map[string]glance.Row{}
	for _, r := range rows {
		got[r.Ticker] = r
	}
	if got["PETR4"].Sev != signals.Look {
		t.Errorf("PETR4 = %+v want Look", got["PETR4"])
	}
	if got["MXRF11"].Sev == signals.Look {
		t.Errorf("MXRF11 should not be Look: %+v", got["MXRF11"])
	}
	if got["XPTO3"].Fail != "No data" {
		t.Errorf("XPTO3 = %+v want No data", got["XPTO3"])
	}
}

func TestMockDrivesScan(t *testing.T) {
	srv := newMockServer(t)
	orig := prices.BaseURL
	t.Cleanup(func() { prices.BaseURL = orig })
	prices.BaseURL = srv.URL + "/prices"

	results := scan.Run([]string{"SCAN1", "XPTO3"}, nil)
	got := map[string]scan.Result{}
	for _, r := range results {
		got[r.Ticker] = r
	}
	if got["XPTO3"].Error != "No data" {
		t.Errorf("XPTO3 = %+v want No data", got["XPTO3"])
	}
	if got["SCAN1"].Error != "" || got["SCAN1"].Readings == nil || got["SCAN1"].Readings.RangePct == nil {
		t.Errorf("SCAN1 = %+v want readings", got["SCAN1"])
	}
}
