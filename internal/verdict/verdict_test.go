package verdict

import (
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/anomaly"
)

func TestDecide(t *testing.T) {
	calm := anomaly.Result{Pct: 0.3, Z: 0.4, Abnormal: false}
	wild := anomaly.Result{Pct: -6.1, Z: -2.8, Abnormal: true}
	cases := []struct {
		a    anomaly.Result
		news bool
		look bool
		must string
	}{
		{calm, false, false, "quiet"},
		{wild, false, true, "-6.1%"},
		{calm, true, true, "news"},
		{wild, true, true, "news"},
	}
	for _, c := range cases {
		d := Decide(c.a, c.news)
		if d.Look != c.look || !strings.Contains(d.Reason, c.must) {
			t.Fatalf("Decide(%+v,%v)=%+v want look=%v ~%q", c.a, c.news, d, c.look, c.must)
		}
	}
}
