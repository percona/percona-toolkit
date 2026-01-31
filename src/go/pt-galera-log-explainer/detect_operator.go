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
	"os/exec"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/rs/zerolog/log"
)

// areOperatorFiles will assume every files are from k8s if one is found
func areOperatorFiles(paths []string) bool {

	for _, path := range paths {

		cmd := exec.Command(CLI.GrepCmd, "-q", "-a", "-m", "1", "^"+types.OperatorLogPrefix, path)
		err := cmd.Run()
		if err == nil {
			return true
		}
		log.Debug().Err(err).Str("path", path).Msg("operator detection result")
	}
	return false
}
