// Package cmd wires the watchman CLI commands.
package cmd

import (
	"os"

	"github.com/spf13/cobra"
)

// version is injected at release time via -ldflags "-X .../cmd.version=...".
var version = "dev"

var rootCmd = &cobra.Command{
	Use:     "wm",
	Short:   "watchman — is this market move noise or worth a look?",
	Version: version,
}

// Run executes the CLI and returns the process exit code. It is the
// testscript-friendly entry point (no os.Exit) so tests can drive wm in-process.
func Run() int {
	if err := rootCmd.Execute(); err != nil {
		return 1
	}
	return 0
}

// Execute runs the CLI and exits the process with the resulting code.
func Execute() {
	if code := Run(); code != 0 {
		os.Exit(code)
	}
}
