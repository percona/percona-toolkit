package main

import (
	"testing"
)

func TestCollectorRegistry(t *testing.T) {
	// Test collector registration
	if len(registeredCollectors) == 0 {
		t.Error("No collectors registered")
	}

	// Verify expected collectors are registered
	expectedCollectors := []string{"mysql", "system"}
	for _, name := range expectedCollectors {
		if _, ok := registeredCollectors[name]; !ok {
			t.Errorf("Expected collector %s not registered", name)
		}
	}
}
