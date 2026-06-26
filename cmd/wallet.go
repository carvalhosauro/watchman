package cmd

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	runList := func(cmd *cobra.Command, _ []string) error {
		ts, err := wallet.List(wallet.Path())
		if err != nil {
			return err
		}
		for _, t := range ts {
			_, _ = fmt.Fprintln(cmd.OutOrStdout(), t)
		}
		return nil
	}

	walletCmd := &cobra.Command{
		Use:   "wallet",
		Short: "manage held tickers",
		Args:  cobra.NoArgs,
		RunE:  runList, // bare `wm wallet` defaults to list
	}

	walletCmd.AddCommand(&cobra.Command{
		Use:   "list",
		Short: "list tickers",
		Args:  cobra.NoArgs,
		RunE:  runList,
	})
	walletCmd.AddCommand(&cobra.Command{
		Use:   "add TICKER [TICKER...]",
		Short: "add one or more tickers",
		Args:  cobra.MinimumNArgs(1),
		RunE:  func(_ *cobra.Command, a []string) error { return wallet.AddMany(wallet.Path(), a...) },
	})
	walletCmd.AddCommand(&cobra.Command{
		Use:   "remove TICKER",
		Short: "remove a ticker",
		Args:  cobra.ExactArgs(1),
		RunE:  func(_ *cobra.Command, a []string) error { return wallet.Remove(wallet.Path(), a[0]) },
	})

	var clearYes bool
	clearCmd := &cobra.Command{
		Use:   "clear",
		Short: "remove all tickers (requires --yes)",
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			if !clearYes {
				return fmt.Errorf("refusing to clear wallet without --yes")
			}
			return wallet.Clear(wallet.Path())
		},
	}
	clearCmd.Flags().BoolVar(&clearYes, "yes", false, "confirm removing all tickers")
	walletCmd.AddCommand(clearCmd)

	rootCmd.AddCommand(walletCmd)
}
