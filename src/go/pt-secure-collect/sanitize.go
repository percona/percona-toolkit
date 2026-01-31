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
	"os"

	"github.com/pkg/errors"

	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize"
	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize/util"
)

func sanitizeFile(opts *cliOptions) error {
	var err error
	ifh := os.Stdin
	ofh := os.Stdout

	if *opts.SanitizeInputFile != "" {
		ifh, err = os.Open(*opts.SanitizeInputFile)
		if err != nil {
			return errors.Wrapf(err, "Cannot open %q for reading", *opts.SanitizeInputFile)
		}
	}

	if *opts.SanitizeOutputFile != "" {
		ofh, err = os.Create(*opts.SanitizeOutputFile)
		if err != nil {
			return errors.Wrapf(err, "Cannot create output file %q", *opts.SanitizeOutputFile)
		}
	}

	lines, err := util.ReadLinesFromFile(ifh)
	if err != nil {
		return errors.Wrapf(err, "Cannot read input file %q", *opts.SanitizeInputFile)
	}

	sanitized := sanitize.Sanitize(lines, !*opts.DontSanitizeHostnames, !*opts.DontSanitizeQueries)

	if err = util.WriteLinesToFile(ofh, sanitized); err != nil {
		return errors.Wrapf(err, "Cannot write output file %q", *opts.SanitizeOutputFile)
	}

	return nil
}
