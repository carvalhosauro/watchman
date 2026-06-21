// Command gen-docs writes shell completions and a man page for wm into
// <dir>/completions and <dir>/manpages. It is run at release time (a GoReleaser
// before-hook) so the artifacts can be bundled into the release archives.
package main

import (
	"log"
	"os"
	"path/filepath"

	"github.com/carvalhosauro/watchman/cmd"
	"github.com/spf13/cobra/doc"
)

func main() {
	if err := generate("."); err != nil {
		log.Fatal(err)
	}
}

// generate writes the completion scripts and man pages under baseDir.
func generate(baseDir string) error {
	root := cmd.Root()
	root.DisableAutoGenTag = true // reproducible output (no timestamp footer)

	comp := filepath.Join(baseDir, "completions")
	man := filepath.Join(baseDir, "manpages")
	for _, d := range []string{comp, man} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}
	if err := root.GenBashCompletionFileV2(filepath.Join(comp, "wm.bash"), true); err != nil {
		return err
	}
	if err := root.GenZshCompletionFile(filepath.Join(comp, "wm.zsh")); err != nil {
		return err
	}
	if err := root.GenFishCompletionFile(filepath.Join(comp, "wm.fish"), true); err != nil {
		return err
	}
	return doc.GenManTree(root, &doc.GenManHeader{Title: "WM", Section: "1"}, man)
}
