package prices

import (
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
