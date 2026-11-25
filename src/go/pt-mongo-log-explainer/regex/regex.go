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

package regex

import (
	"errors"
	"fmt"
	"regexp"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/rs/zerolog/log"
)

var uuidFullRE = regexp.MustCompile(`(?i)^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$`)
var uuidShortRE = regexp.MustCompile(`(?i)^[a-f0-9]{8}-[a-f0-9]{4}$`)
var ipv4RE = regexp.MustCompile(`^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$`)

func internalRegexSubmatch(regex *regexp.Regexp, log string) ([]string, error) {
	slice := regex.FindStringSubmatch(log)
	if len(slice) == 0 {
		return nil, errors.New(fmt.Sprintf("could not find submatch from log \"%s\" using pattern \"%s\"", log, regex.String()))
	}
	return slice, nil
}

func setType(t types.RegexType, regexes types.RegexMap) {
	for _, regex := range regexes {
		regex.Type = t
	}
}

func SetVerbosity(verbosity types.Verbosity, regexes types.RegexMap) {
	for _, regex := range regexes {
		regex.Verbosity = verbosity
	}
}

func AllRegexes() types.RegexMap {
	IdentsMap.Merge(TopologyMap).Merge(ReplicationMap).Merge(EventsMap).Merge(StatesMap).Merge(ClusterMap).Merge(CustomMap)
	return IdentsMap
}

var (
	groupHost      = "host"
	groupPort      = "port"
	groupNodeName  = "nodename"
	groupUUID      = "_id"
	groupMembers   = "members"
	groupVersion   = "version"
	regexHostPort  = "(?P<" + groupHost + `>[a-zA-Z0-9._-]+):(?P<` + groupPort + `>[0-9]{2,6})`
	regexNodeIP    = "(?P<" + groupHost + ">[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})"
	regexNodeName  = "(?P<" + groupNodeName + `>[a-zA-Z0-9._-]+)`
	regexUUID      = "(?P<" + groupUUID + ">[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})"
	regexShortUUID = "(?P<" + groupUUID + ">[a-f0-9]{8}-[a-f0-9]{4})"
	regexMembers   = "(?P<" + groupMembers + ">[0-9]{1,3})"
	regexVersion   = "(?P<" + groupVersion + `>([0-9]+)\.([0-9]+)\.([0-9]+))`
)

func IsNodeUUID(s string) bool {
	return uuidFullRE.MatchString(s) || uuidShortRE.MatchString(s)
}

func IsMongoObjectID(s string) bool {
	b, err := regexp.MatchString(`^[a-fA-F0-9]{24}$`, s)
	if err != nil {
		log.Warn().Err(err).Str("input", s).Msg("failed to check ObjectId")
		return false
	}
	return b
}

func IsNodeIP(s string) bool {
	return ipv4RE.MatchString(s)
}
