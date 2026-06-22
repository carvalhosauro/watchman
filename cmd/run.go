package cmd

import (
	"fmt"
	"time"

	"github.com/carvalhosauro/watchman/internal/config"
	"github.com/carvalhosauro/watchman/internal/glance"
	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	var detail, lookOnly bool
	cmd := &cobra.Command{
		Use:   "run [TICKER...]",
		Short: "fetch and show the noise/look glance",
		RunE: func(cmd *cobra.Command, args []string) error {
			out := cmd.OutOrStdout()
			tickers := args
			if len(tickers) == 0 {
				ts, err := wallet.List(wallet.Path())
				if err != nil {
					return err
				}
				tickers = ts
			}
			if len(tickers) == 0 {
				_, _ = fmt.Fprintln(out, "No tickers. Add with: wm wallet add PETR4")
				return nil
			}
			th, err := config.Load()
			if err != nil {
				return err
			}
			rows := glance.Run(tickers, th)
			if lookOnly {
				rows = glance.OnlyAttention(rows)
			}
			_, _ = fmt.Fprintf(out, "watchman — %s\n", time.Now().UTC().Format("2006-01-02"))
			_, _ = fmt.Fprint(out, glance.Format(rows, detail))
			return nil
		},
	}
	cmd.Flags().BoolVar(&detail, "detail", false, "show every signal per ticker, calm or not")
	cmd.Flags().BoolVar(&lookOnly, "look", false, "show only watch/LOOK rows")
	rootCmd.AddCommand(cmd)
}
