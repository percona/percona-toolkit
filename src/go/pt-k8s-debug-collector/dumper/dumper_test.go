package dumper

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

/*
Unit test for non-existing logs container name error handling
*/

func TestGetIndividualFilesError(t *testing.T) {
	_, err := New("", "", "psmdb", "", "", false)
	if err != nil {
		t.Fatalf("failed to create new dumper: %v", err)
	}

	//err = d.getIndividualFiles("", "", "", "", nil)

	assert.Error(t, err)
	assert.ErrorContains(t, err, "Logs container name is not specified")
}
