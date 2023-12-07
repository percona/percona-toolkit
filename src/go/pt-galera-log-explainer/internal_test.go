package main

import (
	"errors"
	"os"
	"testing"
)

func TestTimelineFromPaths(t *testing.T) {
	tests := []struct {
		path        string
		expectedErr error
	}{
		{
			path:        "tests/logs/",
			expectedErr: errDirectoriesUnsupported,
		},
		{
			path:        "tests/logs/non_existing",
			expectedErr: os.ErrNotExist,
		},
	}

	for _, test := range tests {
		_, err := timelineFromPaths([]string{test.path}, nil)
		if !errors.Is(err, test.expectedErr) {
			t.Fatalf("with path %s, expected error %v, got %v", test.path, test.expectedErr, err)
		}
	}

}
