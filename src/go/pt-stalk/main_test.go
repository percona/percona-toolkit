package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestMainCommand(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "pt-stalk-main-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Test configuration
	cfg := &Config{
		Collectors: "mysql,system",
		Interval:   1,
		RunTime:    2,
		Sleep:      1,
		Dest:       tmpDir,
		Prefix:     "test",
		CollectorConfigs: map[string]interface{}{
			"mysql": &MySQLConfig{
				Host:     "localhost",
				Port:     3306,
				User:     os.Getenv("MYSQL_TEST_USER"),
				Password: os.Getenv("MYSQL_TEST_PASS"),
			},
			"system": &SystemConfig{
				CollectGDB: true,
			},
		},
	}

	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Set up command
	cmd := newRootCmd()
	cmd.SetContext(context.WithValue(ctx, "config", cfg))

	// Execute command
	if err := cmd.Execute(); err != nil && err != context.DeadlineExceeded {
		t.Errorf("Command execution failed: %v", err)
	}

	// Verify output directory structure
	files, err := os.ReadDir(tmpDir)
	if err != nil {
		t.Fatalf("Failed to read output directory: %v", err)
	}

	if len(files) == 0 {
		t.Error("No output files were created")
	}

	// Check for collector outputs
	expectedFiles := map[string]bool{
		"mysql":  false,
		"system": false,
	}

	for _, file := range files {
		if file.IsDir() {
			for collector := range expectedFiles {
				if _, err := os.Stat(filepath.Join(tmpDir, file.Name(), collector)); !os.IsNotExist(err) {
					expectedFiles[collector] = true
				}
			}
		}
	}

	for collector, found := range expectedFiles {
		if !found {
			t.Errorf("Expected output for %s collector not found", collector)
		}
	}
}

func TestMainCommandFlags(t *testing.T) {
	cmd := newRootCmd()

	// Test required flags
	if cmd.Flag("collectors") == nil {
		t.Error("Required flag 'collectors' not found")
	}

	// Test MySQL collector flags
	if cmd.Flag("mysql-host") == nil {
		t.Error("MySQL flag 'mysql-host' not found")
	}
	if cmd.Flag("mysql-port") == nil {
		t.Error("MySQL flag 'mysql-port' not found")
	}

	// Test System collector flags
	if cmd.Flag("collect-gdb") == nil {
		t.Error("System flag 'collect-gdb' not found")
	}
	if cmd.Flag("collect-tcpdump") == nil {
		t.Error("System flag 'collect-tcpdump' not found")
	}
}

func TestMainCommandValidation(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr bool
	}{
		{
			name:    "no collectors",
			args:    []string{},
			wantErr: true,
		},
		{
			name:    "invalid collector",
			args:    []string{"--collectors=invalid"},
			wantErr: true,
		},
		{
			name:    "valid collectors",
			args:    []string{"--collectors=mysql,system"},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := newRootCmd()
			cmd.SetArgs(tt.args)
			err := cmd.Execute()
			if (err != nil) != tt.wantErr {
				t.Errorf("Command execution error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
