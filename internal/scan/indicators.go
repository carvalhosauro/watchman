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

func drawdownPct(bars []prices.Bar) (pct float64, peakDate string, peakClose float64, ok bool) {
	if len(bars) < 2 {
		return 0, "", 0, false
	}
	peak := bars[0].Close
	peakDate = bars[0].Date
	for _, b := range bars {
		if b.Close > peak {
			peak = b.Close
			peakDate = b.Date
		}
	}
	last := bars[len(bars)-1].Close
	if peak == 0 {
		return 0, peakDate, peak, true
	}
	return (last - peak) / peak * 100, peakDate, peak, true
}

const sma200Window = 200

func sma200Pct(bars []prices.Bar) (pct float64, sma float64, ok bool) {
	cs := closeSeries(bars)
	if len(cs) < sma200Window {
		return 0, 0, false
	}
	window := cs[len(cs)-sma200Window:]
	sum := 0.0
	for _, c := range window {
		sum += c
	}
	sma = sum / float64(sma200Window)
	last := cs[len(cs)-1]
	if sma == 0 {
		return 0, sma, true
	}
	return (last - sma) / sma * 100, sma, true
}
