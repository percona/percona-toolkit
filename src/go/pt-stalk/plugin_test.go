package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestPlugin(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pt-stalk-plugin-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create test plugin
	pluginContent := `#!/bin/sh
echo "Test plugin output"
echo "PT_DEST=$PT_DEST"
echo "PT_PREFIX=$PT_PREFIX"
`
	pluginPath := filepath.Join(tmpDir, "test-plugin.sh")
	if err := os.WriteFile(pluginPath, []byte(pluginContent), 0755); err != nil {
		t.Fatal(err)
	}

	cfg := &Config{
		Dest:     tmpDir,
		Prefix:   "test",
		Interval: 1,
		RunTime:  30,
	}

	// Test plugin creation
	plugin, err := NewPlugin(pluginPath, cfg)
	if err != nil {
		t.Fatal(err)
	}

	// Test plugin environment
	plugin.SetEnv("TEST_VAR", "test_value")

	// Test plugin execution
	err = plugin.Execute(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	// Verify plugin output
	outputFile := filepath.Join(tmpDir, "test_plugin.txt")
	content, err := os.ReadFile(outputFile)
	if err != nil {
		t.Fatal(err)
	}

	if len(content) == 0 {
		t.Error("Plugin output is empty")
	}
}

func TestPluginNotFound(t *testing.T) {
	cfg := &Config{
		Dest:   "/tmp",
		Prefix: "test",
	}

	_, err := NewPlugin("/nonexistent/plugin", cfg)
	if err == nil {
		t.Error("Expected error for nonexistent plugin")
	}
}

func TestNoPlugin(t *testing.T) {
	cfg := &Config{
		Dest:   "/tmp",
		Prefix: "test",
	}

	plugin, err := NewPlugin("", cfg)
	if err != nil {
		t.Fatal(err)
	}
	if plugin != nil {
		t.Error("Expected nil plugin when no path provided")
	}
}
