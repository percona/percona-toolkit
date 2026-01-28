package main

import (
	"os"

	"github.com/pkg/errors"

	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize"
	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize/util"
)

type SanitizeCmd struct {
	SanitizeInputFile  string `name:"input-file" help:"Input file. If not specified, the input will be Stdin."`
	SanitizeOutputFile string `name:"output-file" help:"Output file. If not specified, the input will be Stdout."`
	SanitizeHostnames  bool   `name:"sanitize-hostnames" negatable:"" default:"true"`
	SanitizeQueries    bool   `name:"sanitize-queries" negatable:"" default:"true"`
}

func (c *SanitizeCmd) Run() error {
	var err error
	ifh := os.Stdin
	ofh := os.Stdout

	if c.SanitizeInputFile != "" {
		ifh, err = os.Open(c.SanitizeInputFile)
		if err != nil {
			return errors.Wrapf(err, "Cannot open %q for reading", c.SanitizeInputFile)
		}
	}

	if c.SanitizeOutputFile != "" {
		ofh, err = os.Create(c.SanitizeOutputFile)
		if err != nil {
			return errors.Wrapf(err, "Cannot create output file %q", c.SanitizeOutputFile)
		}
	}

	lines, err := util.ReadLinesFromFile(ifh)
	if err != nil {
		return errors.Wrapf(err, "Cannot read input file %q", c.SanitizeInputFile)
	}

	sanitized := sanitize.Sanitize(lines, c.SanitizeHostnames, c.SanitizeQueries)

	if err = util.WriteLinesToFile(ofh, sanitized); err != nil {
		return errors.Wrapf(err, "Cannot write output file %q", c.SanitizeOutputFile)
	}

	return nil
}
