// This program is copyright 2020-2026 Percona LLC and/or its affiliates.
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

package dumper

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

/*
Unit test for non-existing logs container name error handling
*/

func TestGetIndividualFilesError(t *testing.T) {
	d := New("", "", "psmdb", "", "")

	err := d.getIndividualFiles("", "", "", "", nil)

	assert.Error(t, err)
	assert.ErrorContains(t, err, "Logs container name is not specified")
}
