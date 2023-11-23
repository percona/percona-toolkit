package main

import (
	"encoding/json"
	"fmt"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/translate"
)

type ctx struct {
	Paths []string `arg:"" name:"paths" help:"paths of the log to use"`
}

func (c *ctx) Help() string {
	return "Dump the context derived from the log"
}

func (c *ctx) Run() error {

	timeline, err := timelineFromPaths(c.Paths, regex.AllRegexes())
	if err != nil {
		return err
	}

	out := struct {
		DB       any
		Contexts []any
	}{}
	out.DB = translate.GetDB()

	for _, t := range timeline {
		out.Contexts = append(out.Contexts, t[len(t)-1].LogCtx)
	}

	outjson, err := json.MarshalIndent(out, "", "\t")
	if err != nil {
		return err
	}
	fmt.Println(string(outjson))
	return nil
}
