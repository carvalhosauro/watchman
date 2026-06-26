package cmd

import (
	"fmt"
	"strings"

	"github.com/carvalhosauro/watchman"
	"github.com/spf13/cobra"
)

func init() {
	var list bool
	cmd := &cobra.Command{
		Use:   "explain [INDICATOR]",
		Short: "print reference docs for a scan indicator",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			out := cmd.OutOrStdout()
			if list || len(args) == 0 {
				_, _ = fmt.Fprintf(out, "Indicators: %s\n", strings.Join(watchman.IndicatorKeys, ", "))
				_, _ = fmt.Fprintln(out, "Run: wm explain <indicator>")
				return nil
			}
			doc, err := watchman.IndicatorDoc(args[0])
			if err != nil {
				return fmt.Errorf("%w — run 'wm explain --list' to see indicators", err)
			}
			_, _ = fmt.Fprint(out, doc)
			return nil
		},
	}
	cmd.Flags().BoolVar(&list, "list", false, "list indicator keys")
	rootCmd.AddCommand(cmd)
}
