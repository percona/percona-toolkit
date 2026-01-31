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
	"github.com/pkg/errors"
)

type regexList struct {
}

func (l *regexList) Help() string {
	return "List available regexes. Can be used to exclude them later"
}

func (l *regexList) Run() error {

	allregexes := regex.AllRegexes()
	allregexes.Merge(regex.PXCOperatorMap)

	out, err := json.Marshal(&allregexes)
	if err != nil {
		return errors.Wrap(err, "could not marshal regexes")
	}
	fmt.Println(string(out))
	return nil
}
