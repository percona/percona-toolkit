package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestSystemCollector(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pt-stalk-system-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	cfg := &Config{
		Dest:   tmpDir,
		Prefix: "test",
		CollectorConfigs: map[string]interface{}{
			"system": &SystemConfig{
				CollectGDB:     true,
				CollectTcpdump: true,
			},
		},
	}

	collector := NewSystemCollector(cfg)
	err = collector.Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	// Verify system specific files
	expectedFiles := []string{
		"test_diskstats.txt",
		"test_meminfo.txt",
		"test_loadavg.txt",
	}

	for _, file := range expectedFiles {
		path := filepath.Join(tmpDir, file)
		if _, err := os.Stat(path); os.IsNotExist(err) {
			t.Errorf("Expected file not found: %s", file)
		}
	}

	// Verify optional collectors
	if cfg.CollectorConfigs["system"].(*SystemConfig).CollectGDB {
		gdbFile := filepath.Join(tmpDir, "test_gdb.txt")
		if _, err := os.Stat(gdbFile); os.IsNotExist(err) {
			t.Error("Expected GDB file not found")
		}
	}

	if cfg.CollectorConfigs["system"].(*SystemConfig).CollectTcpdump {
		tcpdumpFile := filepath.Join(tmpDir, "test_tcpdump.cap")
		if _, err := os.Stat(tcpdumpFile); os.IsNotExist(err) {
			t.Error("Expected tcpdump file not found")
		}
	}
}
