package main

import (
	"encoding/json"
	"fmt"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/pkg/errors"
	"github.com/rs/zerolog/log"
)

type whois struct {
	Search     string   `arg:"" name:"search" help:"the identifier (node name, ip, uuid) to search"`
	SearchType string   `name:"type" help:"what kind of information is the input (node name, ip, uuid). Auto-detected when possible." enum:"nodename,ip,uuid,auto" default:"auto"`
	Paths      []string `arg:"" name:"paths" help:"paths of the log to use"`
}

func (w *whois) Help() string {
	return `Take any type of info pasted from error logs and find out about it.
It will list known node name(s), IP(s), and other known node's UUIDs.

Regarding UUIDs (wsrep_gcomm_uuid), different format can be found in logs depending on versions : 
- UUID, example: ac0f3910-9790-486c-afd4-845d0ae95692 
- short UUID, with only 1st and 4st part: ac0f3910-afd4
- shortest UUID, with only the 1st part: ac0f3910
`
}

func (w *whois) Run() error {

	if w.SearchType == "auto" {
		if regex.IsNodeUUID(w.Search) {
			w.Search = utils.UUIDToShortUUID(w.Search)
			w.SearchType = "uuid"
		} else if regex.IsNodeIP(w.Search) {
			w.SearchType = "ip"
		} else if len(w.Search) != 8 { // at this point it's only a doubt between names and legacy node uuid, where only the first part of the uuid was shown in log
			w.SearchType = "nodename"
		} else {
			log.Info().Msg("input information's type is ambiguous, scanning files to discover the type. You can also provide --type to avoid auto-detection")
		}
	}

	_, err := timelineFromPaths(CLI.Whois.Paths, regex.AllRegexes())
	if err != nil {
		return errors.Wrap(err, "found nothing to translate")
	}

	if w.SearchType == "auto" {
		if translate.IsNodeUUIDKnown(w.Search) {
			w.SearchType = "uuid"
		} else if translate.IsNodeNameKnown(w.Search) {
			w.SearchType = "nodename"
		} else {
			return errors.New("could not detect the type of input. Try to provide --type. It may means the info is unknown")
		}
	}

	log.Debug().Str("searchType", w.SearchType).Msg("whois searchType")
	out := translate.Whois(w.Search, w.SearchType)

	json, err := json.MarshalIndent(out, "", "\t")
	if err != nil {
		return err
	}
	fmt.Println(string(json))
	return nil
}
