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

package collect

import (
	"bufio"
	"os"
	"os/exec"
	"strings"

	"github.com/pkg/errors"
)

// ForEachLine invokes fn for each line in path. If useGrep is true, only lines matching
// GrepAlternation() are passed (via grep -P); otherwise the whole file is scanned.
func ForEachLine(path, grepCmd string, useGrep bool, fn func(string) error) error {
	if useGrep {
		return forEachLineGrep(path, grepCmd, fn)
	}
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for s.Scan() {
		if err := fn(s.Text()); err != nil {
			return err
		}
	}
	return s.Err()
}

func forEachLineGrep(path, grepCmd string, fn func(string) error) error {
	pat := GrepAlternation()
	cmd := exec.Command(grepCmd, "-a", "-P", pat, path)
	out, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return errors.Wrapf(err, "grep start on %s", path)
	}
	s := bufio.NewScanner(out)
	s.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for s.Scan() {
		line := s.Text()
		if strings.HasPrefix(line, "\t") {
			line = line[1:]
		}
		if err := fn(line); err != nil {
			_ = cmd.Process.Kill()
			return err
		}
	}
	_ = out.Close()
	if err := cmd.Wait(); err != nil {
		if exit, ok := err.(*exec.ExitError); ok && exit.ExitCode() == 1 {
			return nil
		}
		return errors.Wrap(err, "grep")
	}
	return s.Err()
}
