package wallet

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestList(t *testing.T) {
	p := filepath.Join(t.TempDir(), "wallet")
	if err := os.WriteFile(p, []byte("petr4\n\n# fiis\nmxrf11\nITUB4\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := List(p)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"PETR4", "MXRF11", "ITUB4"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestListMissing(t *testing.T) {
	if got, err := List("/no/such/file"); err != nil || len(got) != 0 {
		t.Fatalf("want empty,nil got %v,%v", got, err)
	}
}

func TestPathEnvOverride(t *testing.T) {
	t.Setenv("WATCHMAN_WALLET", "/tmp/x/wallet")
	if Path() != "/tmp/x/wallet" {
		t.Fatalf("env override ignored: %s", Path())
	}
}

func TestAddRemove(t *testing.T) {
	p := filepath.Join(t.TempDir(), "sub", "wallet")
	must := func(err error) {
		if err != nil {
			t.Fatal(err)
		}
	}
	must(Add(p, "petr4"))
	must(Add(p, "PETR4")) // dedupe
	must(Add(p, "mxrf11"))
	must(Remove(p, "petr4"))
	got, _ := List(p)
	if want := []string{"MXRF11"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}
