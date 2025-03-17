package main

import (
	"context"
	"os"
	"path/filepath"
	"sync"

	"github.com/spf13/cobra"
)

type SystemCollector struct {
	stalker   *Stalker
	outDir    string
	prefix    string
	wg        sync.WaitGroup
	systemCfg *SystemConfig
}

func NewSystemCollector(config *Config) Collector {
	systemCfg := config.CollectorConfigs["system"].(*SystemConfig)
	return &SystemCollector{
		stalker:   nil,
		outDir:    config.Dest,
		prefix:    config.Prefix,
		systemCfg: systemCfg,
	}
}

func (c *SystemCollector) Collect(ctx context.Context) error {
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		c.collectDiskStats(ctx)
		c.collectMemInfo(ctx)
		c.collectLoadAvg(ctx)
		if c.systemCfg.CollectGDB {
			c.collectGDB(ctx)
		}
		if c.systemCfg.CollectTcpdump {
			c.collectTcpdump(ctx)
		}
	}()

	c.wg.Wait()
	return nil
}

func (c *SystemCollector) collectDiskStats(ctx context.Context) error {
	return c.readAndWriteFile("/proc/diskstats", c.prefix+"_diskstats.txt")
}

func (c *SystemCollector) collectMemInfo(ctx context.Context) error {
	return c.readAndWriteFile("/proc/meminfo", c.prefix+"_meminfo.txt")
}

func (c *SystemCollector) collectLoadAvg(ctx context.Context) error {
	return c.readAndWriteFile("/proc/loadavg", c.prefix+"_loadavg.txt")
}

func (c *SystemCollector) collectGDB(ctx context.Context) error {
	// GDB collection implementation
	return nil
}

func (c *SystemCollector) collectTcpdump(ctx context.Context) error {
	// Tcpdump collection implementation
	return nil
}

func (c *SystemCollector) readAndWriteFile(srcPath, destName string) error {
	content, err := os.ReadFile(srcPath)
	if err != nil {
		return err
	}

	return os.WriteFile(filepath.Join(c.outDir, destName), content, 0644)
}

type SystemConfig struct {
	CollectGDB      bool
	CollectOProfile bool
	CollectStrace   bool
	CollectTcpdump  bool
}

func addSystemFlags(cmd *cobra.Command, cfg map[string]interface{}) {
	systemCfg := &SystemConfig{}
	cfg["system"] = systemCfg

	cmd.PersistentFlags().BoolVar(&systemCfg.CollectGDB, "collect-gdb", false, "Collect GDB stacktraces")
	cmd.PersistentFlags().BoolVar(&systemCfg.CollectOProfile, "collect-oprofile", false, "Collect OProfile data")
	cmd.PersistentFlags().BoolVar(&systemCfg.CollectStrace, "collect-strace", false, "Collect strace data")
	cmd.PersistentFlags().BoolVar(&systemCfg.CollectTcpdump, "collect-tcpdump", false, "Collect tcpdump data")
}

func init() {
	RegisterCollector(CollectorRegistration{
		Name:         "system",
		AddFlags:     addSystemFlags,
		NewCollector: NewSystemCollector,
	})
}
