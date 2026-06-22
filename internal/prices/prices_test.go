package prices

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

const fixture = `{"chart":{"error":null,"result":[{"timestamp":[1718000000,1718086400,1718172800],"indicators":{"quote":[{"close":[10.0,null,11.0],"volume":[100,200,300]}]}}]}}`

func TestEnvURL(t *testing.T) {
	t.Setenv("WM_TEST_PRICES_URL", "http://mock")
	if got := envURL("WM_TEST_PRICES_URL", "def"); got != "http://mock" {
		t.Fatalf("set: got %q", got)
	}
	if got := envURL("WM_TEST_UNSET_URL", "def"); got != "def" {
		t.Fatalf("unset: got %q", got)
	}
}

func TestParse(t *testing.T) {
	got, err := Parse([]byte(fixture))
	if err != nil {
		t.Fatal(err)
	}
	// the null-close bar is dropped; two bars remain, oldest→newest
	if len(got) != 2 || got[0].Close != 10.0 || got[1].Close != 11.0 || got[1].Volume != 300 {
		t.Fatalf("got %+v", got)
	}
	if got[0].Volume != 100 || got[0].Date != "2024-06-10" {
		t.Fatalf("first bar volume/date wrong: %+v", got[0])
	}
}

func TestParseError(t *testing.T) {
	if _, err := Parse([]byte(`{"chart":{"error":"Not Found","result":null}}`)); err != ErrNoData {
		t.Fatalf("want ErrNoData got %v", err)
	}
}

func TestHistoryFlow(t *testing.T) {
	orig := BaseURL
	t.Cleanup(func() { BaseURL = orig })
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("User-Agent") == "" {
			t.Error("missing User-Agent")
		}
		_, _ = w.Write([]byte(fixture))
	}))
	defer srv.Close()
	BaseURL = srv.URL
	got, err := History("PETR4")
	if err != nil || len(got) != 2 || got[1].Close != 11.0 {
		t.Fatalf("got %+v err %v", got, err)
	}
}

func TestHistoryHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(500) }))
	defer srv.Close()
	old := BaseURL
	BaseURL = srv.URL
	defer func() { BaseURL = old }()

	if _, err := History("PETR4"); err == nil {
		t.Fatal("want error on HTTP 500")
	}
}
