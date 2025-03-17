package main

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestStalkerBasicOperation(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pt-stalk-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	logger := log.New(os.Stderr, "", log.LstdFlags)

	cfg := &Config{
		Collectors: "mysql,system",
		Interval:   1,
		Sleep:      1,
		Dest:       tmpDir,
		Prefix:     "test",
		CollectorConfigs: map[string]interface{}{
			"mysql": &MySQLConfig{
				Host: "localhost",
				Port: 3306,
			},
			"system": &SystemConfig{
				CollectGDB: true,
			},
		},
	}

	stalker, err := NewStalker(cfg, logger)
	if err != nil {
		t.Fatal(err)
	}

	// Run stalker with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	err = stalker.Run(ctx)
	if err != context.DeadlineExceeded {
		t.Errorf("Expected deadline exceeded error, got: %v", err)
	}

	// Verify destination directory was created
	if _, err := os.Stat(tmpDir); os.IsNotExist(err) {
		t.Error("Destination directory was not created")
	}
}

func TestStalkerWithPluginExecution(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pt-stalk-plugin-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create test plugin
	pluginContent := `#!/bin/sh
echo "Test plugin output"
`
	pluginPath := filepath.Join(tmpDir, "test-plugin.sh")
	if err := os.WriteFile(pluginPath, []byte(pluginContent), 0755); err != nil {
		t.Fatal(err)
	}

	logger := log.New(os.Stderr, "", log.LstdFlags)

	cfg := &Config{
		Collectors: "mysql",
		Interval:   1,
		Sleep:      1,
		Dest:       tmpDir,
		Prefix:     "test",
		Plugin:     pluginPath,
		CollectorConfigs: map[string]interface{}{
			"mysql": &MySQLConfig{
				Host: "localhost",
				Port: 3306,
			},
		},
	}

	stalker, err := NewStalker(cfg, logger)
	if err != nil {
		t.Fatal(err)
	}

	// Run stalker with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	err = stalker.Run(ctx)
	if err != context.DeadlineExceeded {
		t.Errorf("Expected deadline exceeded error, got: %v", err)
	}

	// Verify plugin output file exists
	pluginOutput := filepath.Join(tmpDir, "test_plugin.txt")
	if _, err := os.Stat(pluginOutput); os.IsNotExist(err) {
		t.Error("Plugin output file was not created")
	}
}
