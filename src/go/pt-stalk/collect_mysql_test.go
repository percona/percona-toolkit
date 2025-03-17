package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestMySQLCollector(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pt-stalk-mysql-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	cfg := &Config{
		Dest:   tmpDir,
		Prefix: "test",
		CollectorConfigs: map[string]interface{}{
			"mysql": &MySQLConfig{
				Host: "localhost",
				Port: 3306,
				User: "root",
			},
		},
	}

	collector := NewMySQLCollector(cfg)
	err = collector.Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	// Verify MySQL specific files
	expectedFiles := []string{
		"test_status.txt",
		"test_variables.txt",
		"test_processlist.txt",
	}

	for _, file := range expectedFiles {
		path := filepath.Join(tmpDir, file)
		if _, err := os.Stat(path); os.IsNotExist(err) {
			t.Errorf("Expected file not found: %s", file)
		}
	}
}
