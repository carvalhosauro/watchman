// Package wallet stores the tickers the user holds in a plain text file.
package wallet

import (
	"os"
	"path/filepath"
	"strings"
)

// Path is the wallet file location; WATCHMAN_WALLET overrides it (test seam + power users).
func Path() string {
	if p := os.Getenv("WATCHMAN_WALLET"); p != "" {
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "watchman", "wallet")
}

// List returns the held tickers from path: uppercased, trimmed, with blank
// and comment (#) lines skipped. A missing file yields an empty slice.
func List(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return []string{}, nil
		}
		return nil, err
	}
	out := []string{}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, strings.ToUpper(line))
	}
	return out, nil
}

// Add appends ticker (uppercased) to the wallet at path, ignoring duplicates.
func Add(path, ticker string) error { return AddMany(path, ticker) }

// AddMany appends every ticker (uppercased, trimmed) to the wallet at path in a
// single write, skipping blanks and duplicates — both against the existing list
// and within the input.
func AddMany(path string, tickers ...string) error {
	cur, err := List(path)
	if err != nil {
		return err
	}
	seen := make(map[string]bool, len(cur))
	for _, t := range cur {
		seen[t] = true
	}
	for _, t := range tickers {
		t = strings.ToUpper(strings.TrimSpace(t))
		if t == "" || seen[t] {
			continue
		}
		seen[t] = true
		cur = append(cur, t)
	}
	return write(path, cur)
}

// Remove deletes ticker from the wallet at path if present.
func Remove(path, ticker string) error {
	ticker = strings.ToUpper(strings.TrimSpace(ticker))
	cur, err := List(path)
	if err != nil {
		return err
	}
	out := []string{}
	for _, t := range cur {
		if t != ticker {
			out = append(out, t)
		}
	}
	return write(path, out)
}

func write(path string, tickers []string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(strings.Join(tickers, "\n")+"\n"), 0o644)
}
