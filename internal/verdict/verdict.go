// Package verdict reduces a set of signals to one severity + count, with a
// human-readable reason naming the signals that fired.
package verdict

import (
	"strings"

	"github.com/carvalhosauro/watchman/internal/signals"
)

// Decision is the per-ticker call.
type Decision struct {
	Severity signals.Severity
	Count    int
	Reason   string
}

// Decide takes the max severity across signals; Count is how many fired
// (≥ Watch); Reason joins the fired signals' reasons (or "quiet").
func Decide(sigs []signals.Signal) Decision {
	d := Decision{Severity: signals.Calm}
	reasons := make([]string, 0, len(sigs))
	for _, s := range sigs {
		if s.Severity >= signals.Watch {
			d.Count++
			reasons = append(reasons, s.Reason)
			if s.Severity > d.Severity {
				d.Severity = s.Severity
			}
		}
	}
	if len(reasons) == 0 {
		d.Reason = "quiet"
	} else {
		d.Reason = strings.Join(reasons, " · ")
	}
	return d
}
