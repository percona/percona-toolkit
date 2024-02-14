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
