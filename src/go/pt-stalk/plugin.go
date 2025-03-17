package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

type Plugin struct {
	path   string
	config *Config
	env    map[string]string
}

func NewPlugin(path string, config *Config) (*Plugin, error) {
	if path == "" {
		return nil, nil // No plugin configured
	}

	if _, err := os.Stat(path); err != nil {
		return nil, fmt.Errorf("plugin not found: %v", err)
	}

	return &Plugin{
		path:   path,
		config: config,
		env:    make(map[string]string),
	}, nil
}

func (p *Plugin) SetEnv(key, value string) {
	p.env[key] = value
}

func (p *Plugin) Execute(ctx context.Context) error {
	if p == nil {
		return nil // No plugin configured
	}

	cmd := exec.CommandContext(ctx, p.path)

	// Set up environment
	cmd.Env = os.Environ() // Start with current environment
	for k, v := range p.env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	// Add standard plugin environment variables
	cmd.Env = append(cmd.Env,
		fmt.Sprintf("PT_DEST=%s", p.config.Dest),
		fmt.Sprintf("PT_PREFIX=%s", p.config.Prefix),
		fmt.Sprintf("PT_INTERVAL=%d", p.config.Interval),
		fmt.Sprintf("PT_RUNTIME=%d", p.config.RunTime),
	)

	// Set up output
	outputFile := filepath.Join(p.config.Dest, p.config.Prefix+"_plugin.txt")
	output, err := os.Create(outputFile)
	if err != nil {
		return fmt.Errorf("failed to create plugin output file: %v", err)
	}
	defer output.Close()

	cmd.Stdout = output
	cmd.Stderr = output

	// Execute plugin
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("plugin execution failed: %v", err)
	}

	return nil
}
