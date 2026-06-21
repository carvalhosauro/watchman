package cmd

import (
	"fmt"
	"time"

	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(&cobra.Command{
		Use:   "run",
		Short: "fetch and show the noise/look glance",
		RunE: func(cmd *cobra.Command, _ []string) error {
			out := cmd.OutOrStdout() // testable: flow tests capture this
			ts, err := wallet.List(wallet.Path())
			if err != nil {
				return err
			}
			if len(ts) == 0 {
				_, _ = fmt.Fprintln(out, "No tickers. Add with: wm wallet add PETR4")
				return nil
			}
			_, _ = fmt.Fprintf(out, "watchman — %s\n", time.Now().UTC().Format("2006-01-02"))
			_, _ = fmt.Fprint(out, glance.Format(glance.Run(ts)))
			return nil
		},
	})
}
