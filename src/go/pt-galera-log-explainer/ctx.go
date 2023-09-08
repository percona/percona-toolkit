package main

import (
	"encoding/json"
	"fmt"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/regex"
	"github.com/pkg/errors"
)

type ctx struct {
	Paths []string `arg:"" name:"paths" help:"paths of the log to use"`
}

func (c *ctx) Help() string {
	return "Dump the context derived from the log"
}

func (c *ctx) Run() error {

	if len(c.Paths) != 1 {
		return errors.New("Can only use 1 path at a time for ctx subcommand")
	}

	timeline, err := timelineFromPaths(c.Paths, regex.AllRegexes())
	if err != nil {
		return err
	}

	for _, t := range timeline {
		out, err := json.MarshalIndent(t[len(t)-1].Ctx, "", "\t")
		if err != nil {
			return err
		}
		fmt.Println(string(out))
	}

	return nil
}
