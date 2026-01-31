// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

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
