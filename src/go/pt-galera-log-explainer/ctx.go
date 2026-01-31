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
