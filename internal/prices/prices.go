// Package prices fetches trailing daily closes from Yahoo Finance (B3 via ".SA").
package prices

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// httpClient bounds each fetch so a hung upstream can't stall wm run.
var httpClient = &http.Client{Timeout: 10 * time.Second}

// ErrNoData is returned when the response carries no usable price series.
var ErrNoData = errors.New("no price data")

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

// BaseURL is the Yahoo chart endpoint. Tests override it directly (httptest);
// WATCHMAN_PRICES_URL overrides the default for the built binary (e2e mocking).
var BaseURL = envURL("WATCHMAN_PRICES_URL", "https://query1.finance.yahoo.com/v8/finance/chart")

func envURL(key, def string) string {
	if u := os.Getenv(key); u != "" {
		return u
	}
	return def
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
