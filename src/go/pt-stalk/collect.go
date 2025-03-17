package main

import (
	"context"

	"github.com/spf13/cobra"
)

type CollectorRegistration struct {
	Name         string
	AddFlags     func(*cobra.Command, map[string]interface{})
	NewCollector func(*Config) Collector
}

var registeredCollectors = make(map[string]CollectorRegistration)

func RegisterCollector(reg CollectorRegistration) {
	registeredCollectors[reg.Name] = reg
}

// Base interface that all collectors must implement
type Collector interface {
	Collect(ctx context.Context) error
}
