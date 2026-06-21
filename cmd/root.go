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

// Root returns the root command with all subcommands attached (registered via
// each command file's init). Used by the docs/completions generator.
func Root() *cobra.Command { return rootCmd }

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
