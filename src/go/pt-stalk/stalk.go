package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"
)

type Stalker struct {
	config *Config
	logger *log.Logger
	plugin *Plugin
}

func NewStalker(config *Config, logger *log.Logger) (*Stalker, error) {
	s := &Stalker{
		config: config,
		logger: logger,
	}

	// Initialize plugin if configured
	if config.Plugin != "" {
		plugin, err := NewPlugin(config.Plugin, config)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize plugin: %v", err)
		}
		s.plugin = plugin
	}

	return s, nil
}

func (s *Stalker) Run(ctx context.Context) error {
	// Create destination directory if it doesn't exist
	if err := os.MkdirAll(s.config.Dest, 0755); err != nil {
		return fmt.Errorf("failed to create destination directory: %v", err)
	}

	// Main collection loop
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			if err := s.runCollectors(ctx); err != nil {
				s.logger.Printf("Collection error: %v", err)
			}
			time.Sleep(time.Duration(s.config.Sleep) * time.Second)
		}
	}
}

func (s *Stalker) runCollectors(ctx context.Context) error {
	// Run collectors
	enabledCollectors := strings.Split(s.config.Collectors, ",")
	for _, name := range enabledCollectors {
		name = strings.TrimSpace(name)
		if reg, ok := registeredCollectors[name]; ok {
			collector := reg.NewCollector(s.config)
			if err := collector.Collect(ctx); err != nil {
				return fmt.Errorf("collector %s failed: %v", name, err)
			}
		}
	}

	// Run plugin if configured
	if s.plugin != nil {
		if err := s.plugin.Execute(ctx); err != nil {
			return fmt.Errorf("plugin execution failed: %v", err)
		}
	}

	return nil
}
