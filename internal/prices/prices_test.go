package prices

import (
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
)

const fixture = `{"chart":{"error":null,"result":[{"indicators":{"quote":[{"close":[10.0,10.5,null,11.0]}]}}]}}`

func TestParse(t *testing.T) {
	got, err := Parse([]byte(fixture))
	if err != nil {
		t.Fatal(err)
	}
	if want := []float64{10.0, 10.5, 11.0}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestParseError(t *testing.T) {
	if _, err := Parse([]byte(`{"chart":{"error":"Not Found","result":null}}`)); err != ErrNoData {
		t.Fatalf("want ErrNoData got %v", err)
	}
}

func TestHistoryFlow(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("User-Agent") == "" {
			t.Error("missing User-Agent")
		}
		_, _ = w.Write([]byte(fixture))
	}))
	defer srv.Close()
	old := BaseURL
	BaseURL = srv.URL
	defer func() { BaseURL = old }()

	got, err := History("PETR4")
	if err != nil || len(got) != 3 || got[2] != 11.0 {
		t.Fatalf("got %v err %v", got, err)
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
