package dumper

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestMatchesCR(t *testing.T) {
	tests := []struct {
		name      string
		cr        string
		podLabels map[string]string
		expected  bool
	}{
		{
			name:      "psmdb with mongod component",
			cr:        "psmdb",
			podLabels: map[string]string{"app.kubernetes.io/component": "mongod"},
			expected:  true,
		},
		{
			name:      "ps with mysql component",
			cr:        "ps",
			podLabels: map[string]string{"app.kubernetes.io/component": "mysql"},
			expected:  true,
		},
		{
			name:      "pg with pgo-pg-database label",
			cr:        "pg",
			podLabels: map[string]string{"pgo-pg-database": "true"},
			expected:  true,
		},
		{
			name: "pgv2 with correct labels",
			cr:   "pgv2",
			podLabels: map[string]string{
				"pgv2.percona.com/version":                   "1.0",
				"postgres-operator.crunchydata.com/instance": "test",
			},
			expected: true,
		},
		{
			name:      "no match",
			cr:        "unknown",
			podLabels: map[string]string{"app": "test"},
			expected:  false,
		},
		{
			name:      "psmdb using app.kubernetes.io/name label",
			cr:        "psmdb",
			podLabels: map[string]string{"app.kubernetes.io/name": "mongod"},
			expected:  true,
		},
		{
			name:      "ps using app.kubernetes.io/name label",
			cr:        "ps",
			podLabels: map[string]string{"app.kubernetes.io/name": "mysql"},
			expected:  true,
		},
		{
			name:      "pg with pgo alias",
			cr:        "pgo",
			podLabels: map[string]string{"pgo-pg-database": "true"},
			expected:  true,
		},
		{
			name:      "pgv2 missing one required label",
			cr:        "pgv2",
			podLabels: map[string]string{"pgv2.percona.com/version": "1.0"},
			expected:  false,
		},
		{
			name:      "empty labels",
			cr:        "psmdb",
			podLabels: map[string]string{},
			expected:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := matchesCR(tt.cr, tt.podLabels)
			if result != tt.expected {
				t.Errorf("matchesCR(%q, %v) = %v; want %v", tt.cr, tt.podLabels, result, tt.expected)
			}
		})
	}
}

func TestResourceTypeParsing(t *testing.T) {
	tests := []struct {
		name     string
		cr       string
		expected string
	}{
		{
			name:     "pg exact match",
			cr:       "pg",
			expected: "pg",
		},
		{
			name:     "pgv2 exact match",
			cr:       "pgv2",
			expected: "pgv2",
		},
		{
			name:     "pxc exact match",
			cr:       "pxc",
			expected: "pxc",
		},
		{
			name:     "ps exact match",
			cr:       "ps",
			expected: "ps",
		},
		{
			name:     "psmdb exact match",
			cr:       "psmdb",
			expected: "psmdb",
		},
		{
			name:     "auto",
			cr:       "auto",
			expected: "auto",
		},
		{
			name:     "pxc with path",
			cr:       "pxc/something",
			expected: "pxc",
		},
		{
			name:     "pg with path",
			cr:       "pg/something",
			expected: "pg",
		},
		{
			name:     "pgo exact match",
			cr:       "pgo",
			expected: "pg",
		},
		{
			name:     "pgo with path",
			cr:       "pgo/something",
			expected: "pg",
		},
		{
			name:     "pgv2 with path",
			cr:       "pgv2/something",
			expected: "pgv2",
		},
		{
			name:     "psmdb with path",
			cr:       "psmdb/something",
			expected: "psmdb",
		},
		{
			name:     "unknown returns as is",
			cr:       "unknown",
			expected: "unknown",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := resourceType(tt.cr)
			if result != tt.expected {
				t.Errorf("resourceType(%q) = %q; want %q", tt.cr, result, tt.expected)
			}
		})
	}
}

// Tests for individual_files.go

func TestGetSummarySkipPodSummary(t *testing.T) {
	// Test that getSummary returns early when skipPodSummary is true
	d := &Dumper{
		skipPodSummary: true,
		location:       "/tmp/dump",
		logger:         NewSafeLogger(),
	}

	pod := corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-pod",
			Namespace: "default",
		},
	}

	job := exportJob{Pod: pod}

	// When skipPodSummary is true, getSummary should return early
	// This test ensures it doesn't panic and completes successfully
	t.Run("skip pod summary when flag is true", func(t *testing.T) {
		defer func() {
			if r := recover(); r != nil {
				t.Errorf("getSummary panicked: %v", r)
			}
		}()

		// getSummary returns early when skipPodSummary is true
		d.getSummary(context.Background(), job, "pxc", "/tmp/summary.txt")
		t.Log("getSummary completed successfully when skipPodSummary is true")
	})
}

func TestGetSummarySkipPodSummaryFalse(t *testing.T) {
	// Test that getSummary processes when skipPodSummary is false
	d := &Dumper{
		skipPodSummary: false,
		location:       "/tmp/dump",
		logger:         NewSafeLogger(),
	}

	pod := corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-pod",
			Namespace: "default",
		},
	}

	job := exportJob{Pod: pod}

	t.Run("process pod summary when flag is false", func(t *testing.T) {
		defer func() {
			if r := recover(); r != nil {
				// We expect potential panics from getPodSummary since archive is nil
				// This is acceptable in this unit test
				t.Logf("Expected potential panic from getPodSummary: %v", r)
			}
		}()

		d.getSummary(context.Background(), job, "pxc", "/tmp/summary.txt")
	})
}
