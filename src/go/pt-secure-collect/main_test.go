// This program is copyright 2018-2026 Percona LLC and/or its affiliates.
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
	out, err := exec.Command("../../../bin/"+toolname, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(toolname + `\n.*Version v?\d+\.\d+\.\d+\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", toolname, out)
	}
}
