// Package verdict is the deterministic ignore/LOOK rule. You can read why it fired.
package verdict

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/anomaly"
)

// Decision is the per-ticker call: Look says "worth a look", Reason explains why.
type Decision struct {
	Look   bool
	Reason string
}

// Decide applies the ordered rule: fresh news always escalates, an abnormal
// move escalates, otherwise it's noise to ignore.
func Decide(a anomaly.Result, hasNews bool) Decision {
	move := fmt.Sprintf("%.1f%% (%.1fσ/30d)", a.Pct, a.Z)
	switch {
	case a.Abnormal && hasNews:
		return Decision{true, "moved " + move + " + fresh material news"}
	case hasNews:
		return Decision{true, "fresh material news"}
	case a.Abnormal:
		return Decision{true, "moved " + move + " vs 30d"}
	default:
		return Decision{false, "quiet (" + move + ")"}
	}
}
