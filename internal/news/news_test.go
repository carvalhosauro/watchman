package news

import "testing"

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
