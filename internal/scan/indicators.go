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

const rsiPeriod = 14

func rsiValue(bars []prices.Bar) (float64, bool) {
	cs := closeSeries(bars)
	if len(cs) < rsiPeriod+1 {
		return 0, false
	}
	var gain, loss float64
	for i := 1; i <= rsiPeriod; i++ {
		d := cs[i] - cs[i-1]
		if d >= 0 {
			gain += d
		} else {
			loss -= d
		}
	}
	avgGain, avgLoss := gain/rsiPeriod, loss/rsiPeriod
	for i := rsiPeriod + 1; i < len(cs); i++ {
		d := cs[i] - cs[i-1]
		g, l := 0.0, 0.0
		if d >= 0 {
			g = d
		} else {
			l = -d
		}
		avgGain = (avgGain*(rsiPeriod-1) + g) / rsiPeriod
		avgLoss = (avgLoss*(rsiPeriod-1) + l) / rsiPeriod
	}
	if avgLoss == 0 {
		return 100, true
	}
	return 100 - 100/(1+avgGain/avgLoss), true
}

const volWindow = 20

func volumeRatio(bars []prices.Bar) (float64, bool) {
	if len(bars) < volWindow+1 {
		return 0, false
	}
	window := bars[len(bars)-volWindow-1 : len(bars)-1]
	var sum float64
	for _, b := range window {
		sum += b.Volume
	}
	avg := sum / float64(volWindow)
	if avg == 0 {
		return 0, false
	}
	return bars[len(bars)-1].Volume / avg, true
}
