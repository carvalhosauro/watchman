package cmd

import (
	"fmt"

	"github.com/carvalhosauro/watchman/internal/wallet"
	"github.com/spf13/cobra"
)

func init() {
	walletCmd := &cobra.Command{Use: "wallet", Short: "manage held tickers"}

	walletCmd.AddCommand(&cobra.Command{
		Use:   "list",
		Short: "list tickers",
		RunE: func(cmd *cobra.Command, _ []string) error {
			ts, err := wallet.List(wallet.Path())
			if err != nil {
				return err
			}
			for _, t := range ts {
				fmt.Fprintln(cmd.OutOrStdout(), t)
			}
			return nil
		},
	})
	walletCmd.AddCommand(&cobra.Command{
		Use:   "add TICKER",
		Short: "add a ticker",
		Args:  cobra.ExactArgs(1),
		RunE:  func(_ *cobra.Command, a []string) error { return wallet.Add(wallet.Path(), a[0]) },
	})
	walletCmd.AddCommand(&cobra.Command{
		Use:   "remove TICKER",
		Short: "remove a ticker",
		Args:  cobra.ExactArgs(1),
		RunE:  func(_ *cobra.Command, a []string) error { return wallet.Remove(wallet.Path(), a[0]) },
	})
	rootCmd.AddCommand(walletCmd)
}
