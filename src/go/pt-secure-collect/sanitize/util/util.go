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

package util

import (
	"bufio"
	"bytes"
	"encoding/gob"
	"os"
	"strings"

	"github.com/pkg/errors"
)

func ReadLinesFromFile(fh *os.File) ([]string, error) {
	lines := []string{}
	reader := bufio.NewReader(fh)

	line, err := reader.ReadString('\n')
	for err == nil {
		lines = append(lines, strings.TrimRight(line, "\n"))
		line, err = reader.ReadString('\n')
	}
	return lines, nil
}

func WriteLinesToFile(ofh *os.File, lines []string) error {
	for _, line := range lines {
		if _, err := ofh.WriteString(line + "\n"); err != nil {
			return errors.Wrap(err, "Cannot write output file")
		}
	}
	return nil
}

func LinesToBytes(lines []string) []byte {
	buf := &bytes.Buffer{}
	gob.NewEncoder(buf).Encode(lines)
	return buf.Bytes()
}

func BytesToLines(buf []byte) []string {
	reader := bytes.NewReader(buf)
	lines := []string{}
	gob.NewDecoder(reader).Decode(&lines)
	return lines
}
