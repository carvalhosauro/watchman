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

// Execute runs the CLI.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
