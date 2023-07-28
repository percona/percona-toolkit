package main

import (
	"bufio"
	"bytes"
	"os"
	"os/exec"
	"reflect"
	"regexp"
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

/*
Option --version
*/
func TestVersionOption(t *testing.T) {
	out, err := exec.Command("../../../bin/"+TOOLNAME, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", TOOLNAME, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(TOOLNAME + `\n.*Version v?\d+\.\d+\.\d+\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", TOOLNAME, out)
	}
}
