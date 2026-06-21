// Command wm is the watchman CLI entry point.
package main

import (
	"os"

	"github.com/carvalhosauro/watchman/cmd"
)

func main() { os.Exit(cmd.Run()) }
