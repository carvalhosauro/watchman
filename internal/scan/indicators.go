package scan

import "github.com/carvalhosauro/watchman/internal/prices"

const rangeMinBars = 200

func rangePct(bars []prices.Bar) (float64, bool) {
	cs := closeSeries(bars)
	if len(cs) < rangeMinBars {
		return 0, false
	}
	hi, lo := cs[0], cs[0]
	for _, c := range cs {
		if c > hi {
			hi = c
		}
		if c < lo {
			lo = c
		}
	}
	if hi == lo {
		return 0, true
	}
	last := cs[len(cs)-1]
	return (last - lo) / (hi - lo) * 100, true
}
