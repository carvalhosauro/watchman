// Package news reads the CVM material-fact feed: fresh news for this ticker today?
package news

import (
	"encoding/xml"
	"strings"
	"time"
)

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

func parseDate(pub string) string {
	for _, layout := range []string{time.RFC1123, "Mon, 2 Jan 2006 15:04:05 MST"} {
		if t, err := time.Parse(layout, pub); err == nil {
			return t.UTC().Format("2006-01-02")
		}
	}
	return ""
}
