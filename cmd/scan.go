package cmd

import (
	"fmt"
	"time"

	"github.com/carvalhosauro/watchman/internal/scan"
	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	var detail, asJSON bool
	cmd := &cobra.Command{
		Use:   "scan [TICKER...]",
		Short: "show neutral technical readout for watched tickers",
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
			results := scan.Run(tickers, nil)
			date := time.Now().UTC().Format("2006-01-02")
			if asJSON {
				s, err := scan.FormatJSON(date, results)
				if err != nil {
					return err
				}
				_, _ = fmt.Fprint(out, s)
				return nil
			}
			header := scan.FormatHeader(date, len(tickers))
			if detail {
				_, _ = fmt.Fprint(out, header)
				_, _ = fmt.Fprint(out, scan.FormatDetailAll(results))
				return nil
			}
			_, _ = fmt.Fprint(out, header)
			_, _ = fmt.Fprint(out, scan.FormatTableBody(results))
			return nil
		},
	}
	cmd.Flags().BoolVar(&detail, "detail", false, "expanded per-ticker readout")
	cmd.Flags().BoolVar(&asJSON, "json", false, "machine-readable JSON output")
	rootCmd.AddCommand(cmd)
}
