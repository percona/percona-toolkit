package main

import (
	"bufio"
	"bytes"
	"os"
	"reflect"
	"testing"
)

func TestProcessCliParams(t *testing.T) {
	var output bytes.Buffer
	writer := bufio.NewWriter(&output)

	tests := []struct {
		Args     []string
		WantOpts *cliOptions
		WantErr  bool
	}{
		{
			Args:     []string{"pt-sanitize-data", "llll"},
			WantOpts: nil,
			WantErr:  true,
		},
	}

	for i, test := range tests {
		os.Args = test.Args
		opts, err := processCliParams(os.TempDir(), writer)
		writer.Flush()
		if test.WantErr && err == nil {
			t.Errorf("Test #%d expected error, have nil", i)
		}
		if !reflect.DeepEqual(opts, test.WantOpts) {

		}
	}
}

func TestCollect(t *testing.T) {

}
