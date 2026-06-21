package news

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

const xmlFix = `<rss><channel>
<item><title>PETR4 - Fato Relevante sobre dividendos</title><pubDate>Sat, 20 Jun 2026 09:00:00 GMT</pubDate></item>
<item><title>VALE3 - Comunicado</title><pubDate>Fri, 19 Jun 2026 18:00:00 GMT</pubDate></item>
</channel></rss>`

func TestParseAndFresh(t *testing.T) {
	items, err := ParseItems([]byte(xmlFix))
	if err != nil || len(items) != 2 {
		t.Fatalf("items=%v err=%v", items, err)
	}
	if items[0].Date != "2026-06-20" {
		t.Fatalf("date=%q", items[0].Date)
	}
	if !Fresh("PETR4", items, "2026-06-20") {
		t.Fatal("PETR4 should be fresh")
	}
	if Fresh("VALE3", items, "2026-06-20") || Fresh("ITUB4", items, "2026-06-20") {
		t.Fatal("only PETR4 fresh today")
	}
}

func TestFetchItemsFlow(t *testing.T) {
	orig := FeedURL
	t.Cleanup(func() { FeedURL = orig })
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(xmlFix))
	}))
	defer srv.Close()
	FeedURL = srv.URL

	items := FetchItems()
	if len(items) != 2 || items[0].Date != "2026-06-20" {
		t.Fatalf("got %v", items)
	}
}

func TestFetchItemsGraceful(t *testing.T) {
	orig := FeedURL
	t.Cleanup(func() { FeedURL = orig })
	dead := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	FeedURL = dead.URL
	dead.Close() // closed server → connection refused at once, exercises the graceful nil path
	if items := FetchItems(); items != nil {
		t.Fatalf("want nil on failure, got %v", items)
	}
}
