package anomaly

import "testing"

func TestAbnormal(t *testing.T) {
	closes := make([]float64, 30)
	for i := range closes {
		closes[i] = 10.0
	}
	closes = append(closes, 13.0)
	r, err := Analyze(closes)
	if err != nil {
		t.Fatal(err)
	}
	if !r.Abnormal || r.Z <= 2.0 {
		t.Fatalf("got %+v", r)
	}
}

func TestCalm(t *testing.T) {
	closes := make([]float64, 40)
	for i := range closes {
		closes[i] = 10.0 + 0.01*float64(i%3)
	}
	if r, _ := Analyze(closes); r.Abnormal {
		t.Fatalf("got %+v", r)
	}
}

func TestInsufficient(t *testing.T) {
	if _, err := Analyze([]float64{10}); err != ErrInsufficient {
		t.Fatalf("got %v", err)
	}
}
