package verdict

import (
	"strings"
	"testing"

	"github.com/carvalhosauro/watchman/internal/signals"
)

func TestDecide(t *testing.T) {
	in := []signals.Signal{
		{Name: "zscore", Severity: signals.Look, Reason: "-6.1% (2.8σ)"},
		{Name: "rsi", Severity: signals.Watch, Reason: "RSI 72"},
		{Name: "volume", Severity: signals.Calm, Reason: "vol 1.1×"},
	}
	d := Decide(in)
	if d.Severity != signals.Look {
		t.Fatalf("severity=%v", d.Severity)
	}
	if d.Count != 2 { // Look + Watch fired; Calm doesn't count
		t.Fatalf("count=%d", d.Count)
	}
	if !strings.Contains(d.Reason, "2.8σ") || strings.Contains(d.Reason, "1.1×") {
		t.Fatalf("reason=%q", d.Reason)
	}
}

func TestDecideCalm(t *testing.T) {
	d := Decide([]signals.Signal{{Name: "zscore", Severity: signals.Calm}})
	if d.Severity != signals.Calm || d.Count != 0 {
		t.Fatalf("got %+v", d)
	}
	if d.Reason != "quiet" {
		t.Fatalf("reason=%q", d.Reason)
	}
}
