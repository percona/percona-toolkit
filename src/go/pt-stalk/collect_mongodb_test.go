package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMongoDBCollector(t *testing.T) {
	// Skip if no MongoDB connection available
	mongoURI := os.Getenv("TEST_MONGODB_URI")
	if mongoURI == "" {
		t.Skip("Skipping MongoDB tests: TEST_MONGODB_URI not set")
	}

	// Create temp directory for test outputs
	tmpDir, err := os.MkdirTemp("", "mongodb-collector-test")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create test config
	cfg := &Config{
		Dest:   tmpDir,
		Prefix: "test",
		CollectorConfigs: map[string]interface{}{
			"mongodb": &MongoDBConfig{
				Host:     "localhost",
				Port:     27017,
				User:     "testuser",
				Password: "testpass",
			},
		},
	}

	// Create collector
	collector := NewMongoDBCollector(cfg)
	assert.NotNil(t, collector)

	// Test collection
	ctx := context.Background()
	err = collector.Collect(ctx)
	assert.NoError(t, err)

	// Verify output files exist
	expectedFiles := []string{
		"test_server_status.txt",
		"test_current_op.txt",
		"test_db_stats.txt",
	}

	for _, file := range expectedFiles {
		path := filepath.Join(tmpDir, file)
		_, err := os.Stat(path)
		assert.NoError(t, err, "Expected file %s to exist", file)

		// Verify file is not empty
		content, err := os.ReadFile(path)
		assert.NoError(t, err)
		assert.NotEmpty(t, content)
	}
}

func TestMongoDBCollectorConnection(t *testing.T) {
	// Test invalid connection
	cfg := &Config{
		Dest:   os.TempDir(),
		Prefix: "test",
		CollectorConfigs: map[string]interface{}{
			"mongodb": &MongoDBConfig{
				Host:     "nonexistent",
				Port:     27017,
				User:     "invalid",
				Password: "invalid",
			},
		},
	}

	collector := NewMongoDBCollector(cfg)
	err := collector.Collect(context.Background())
	assert.Error(t, err)
}
