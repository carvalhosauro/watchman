package watchman

import (
	"strings"
	"testing"
)

func TestIndicatorDocLoadsEachKey(t *testing.T) {
	for _, k := range IndicatorKeys {
		doc, err := IndicatorDoc(k)
		if err != nil {
			t.Fatalf("IndicatorDoc(%q) error: %v", k, err)
		}
		if strings.TrimSpace(doc) == "" {
			t.Fatalf("IndicatorDoc(%q) returned empty", k)
		}
	}
}

func TestIndicatorDocUnknown(t *testing.T) {
	if _, err := IndicatorDoc("bogus"); err == nil {
		t.Fatal("want error for unknown indicator")
	}
}
