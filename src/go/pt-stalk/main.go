package main

import (
	"fmt"
	"log"
	"os"

	"github.com/spf13/cobra"
)

type Config struct {
	// Common configuration only
	Collectors     string
	Interval       int
	RunTime        int
	Sleep          int
	SleepCollect   int
	Dest           string
	Prefix         string
	Log            string
	Pid            string
	Daemonize      bool
	RetentionTime  int
	RetentionCount int
	RetentionSize  int
	DiskBytesFree  int64
	DiskPctFree    int
	NotifyByEmail  string
	Verbose        int
	Plugin         string

	// Collector configs
	CollectorConfigs map[string]interface{}
}

func newRootCmd() *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "pt-stalk",
		Short: "MySQL and system metrics collector",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := cmd.Context().Value("config").(*Config)
			logger := log.New(os.Stderr, "", log.LstdFlags)

			stalker, err := NewStalker(cfg, logger)
			if err != nil {
				return fmt.Errorf("failed to initialize stalker: %v", err)
			}

			return stalker.Run(cmd.Context())
		},
	}

	cfg := &Config{
		CollectorConfigs: make(map[string]interface{}),
	}

	rootCmd.PersistentFlags().StringVar(&cfg.Collectors, "collectors", "", "Comma-separated list of collectors to enable (mysql,system)")
	rootCmd.PersistentFlags().IntVar(&cfg.Interval, "interval", 1, "Check interval in seconds")
	rootCmd.PersistentFlags().IntVar(&cfg.RunTime, "run-time", 30, "How long to collect data in seconds")
	rootCmd.PersistentFlags().IntVar(&cfg.Sleep, "sleep", 1, "Sleep time between collections in seconds")
	rootCmd.PersistentFlags().StringVar(&cfg.Dest, "dest", "/var/lib/pt-stalk", "Destination directory for collected data")
	rootCmd.PersistentFlags().StringVar(&cfg.Prefix, "prefix", "", "Filename prefix for samples")
	rootCmd.PersistentFlags().StringVar(&cfg.Log, "log", "/var/log/pt-stalk.log", "Log file when daemonized")
	rootCmd.PersistentFlags().StringVar(&cfg.Pid, "pid", "/var/run/pt-stalk.pid", "PID file")
	rootCmd.PersistentFlags().BoolVar(&cfg.Daemonize, "daemonize", false, "Run as daemon")
	rootCmd.PersistentFlags().IntVar(&cfg.RetentionTime, "retention-time", 30, "Days to retain samples")
	rootCmd.PersistentFlags().IntVar(&cfg.RetentionCount, "retention-count", 0, "Number of samples to retain")
	rootCmd.PersistentFlags().IntVar(&cfg.RetentionSize, "retention-size", 0, "Maximum size in MB to retain")
	rootCmd.PersistentFlags().Int64Var(&cfg.DiskBytesFree, "disk-bytes-free", 100*1024*1024, "Minimum bytes free")
	rootCmd.PersistentFlags().IntVar(&cfg.DiskPctFree, "disk-pct-free", 5, "Minimum percent free")
	rootCmd.PersistentFlags().StringVar(&cfg.NotifyByEmail, "notify-by-email", "", "Email address for notifications")
	rootCmd.PersistentFlags().IntVar(&cfg.Verbose, "verbose", 2, "Verbosity level (0-3)")
	rootCmd.PersistentFlags().StringVar(&cfg.Plugin, "plugin", "", "Path to plugin script")

	// Add collector-specific flags
	for _, reg := range registeredCollectors {
		reg.AddFlags(rootCmd, cfg.CollectorConfigs)
	}

	return rootCmd
}

func main() {
	cmd := newRootCmd()
	if err := cmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
