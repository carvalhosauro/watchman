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
