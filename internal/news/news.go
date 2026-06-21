// Package news reads the CVM material-fact feed: fresh news for this ticker today?
package news

import (
	"encoding/xml"
	"io"
	"net/http"
	"strings"
	"time"
)

// httpClient bounds the feed fetch so a hung upstream can't stall wm run.
var httpClient = &http.Client{Timeout: 10 * time.Second}

// FeedURL is the CVM material-fact source; overridable in tests (httptest).
// Default = CVM RAD endpoint (see reference lib/watchman/news/cvm.ex). Note: the
// live RAD payload is <CVM><documento> rather than the RSS <channel><item> this
// package parses, so a live fetch yields zero items today and the glance falls
// back to price-only — graceful by design until the RSS feed URL is wired.
var FeedURL = "https://www.rad.cvm.gov.br/ENETCONSULTA/frmGetXml.aspx?TipoConsulta=c&CodigoInstituicao=1"

// Item is a single feed entry reduced to what the verdict needs.
type Item struct {
	Title string
	Date  string // "2006-01-02"
}

type rss struct {
	Items []struct {
		Title   string `xml:"title"`
		PubDate string `xml:"pubDate"`
	} `xml:"channel>item"`
}

// ParseItems decodes an RSS body into items with normalized dates.
func ParseItems(body []byte) ([]Item, error) {
	var r rss
	if err := xml.Unmarshal(body, &r); err != nil {
		return nil, err
	}
	out := make([]Item, 0, len(r.Items))
	for _, it := range r.Items {
		out = append(out, Item{Title: it.Title, Date: parseDate(it.PubDate)})
	}
	return out, nil
}

// Fresh reports whether a ticker has a same-day item by title substring match.
func Fresh(ticker string, items []Item, today string) bool {
	for _, it := range items {
		if it.Date == today && strings.Contains(it.Title, ticker) {
			return true
		}
	}
	return false
}

// FetchItems GETs the feed once per run and returns parsed items, or nil on any
// failure (network, status, read, parse). News is a soft signal: never error up.
func FetchItems() []Item {
	req, err := http.NewRequest(http.MethodGet, FeedURL, nil)
	if err != nil {
		return nil
	}
	req.Header.Set("User-Agent", "watchman/2.0")
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil
	}
	items, err := ParseItems(body)
	if err != nil {
		return nil
	}
	return items
}

func parseDate(pub string) string {
	for _, layout := range []string{time.RFC1123, "Mon, 2 Jan 2006 15:04:05 MST"} {
		if t, err := time.Parse(layout, pub); err == nil {
			return t.UTC().Format("2006-01-02")
		}
	}
	return ""
}
