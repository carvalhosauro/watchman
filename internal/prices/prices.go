// Package prices fetches trailing daily closes from Yahoo Finance (B3 via ".SA").
package prices

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

// ErrNoData is returned when the response carries no usable price series.
var ErrNoData = errors.New("no price data")

type chartResp struct {
	Chart struct {
		Error  any `json:"error"`
		Result []struct {
			Indicators struct {
				Quote []struct {
					Close []*float64 `json:"close"`
				} `json:"quote"`
			} `json:"indicators"`
		} `json:"result"`
	} `json:"chart"`
}

// Parse extracts daily closes (oldest→newest, nils dropped) from a Yahoo chart payload.
func Parse(body []byte) ([]float64, error) {
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
	out := []float64{}
	for _, c := range r.Chart.Result[0].Indicators.Quote[0].Close {
		if c != nil {
			out = append(out, *c)
		}
	}
	return out, nil
}

// BaseURL is overridable in tests (httptest); default = Yahoo Finance chart API.
var BaseURL = "https://query1.finance.yahoo.com/v8/finance/chart"

// History fetches recent daily closes for ticker from Yahoo Finance.
func History(ticker string) ([]float64, error) {
	url := fmt.Sprintf("%s/%s.SA?range=2mo&interval=1d", BaseURL, ticker)
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("User-Agent", "watchman/2.0")
	resp, err := http.DefaultClient.Do(req)
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
