package regex

import (
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/rs/zerolog/log"
)

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
	return
}

// SetVerbosity accepts any LogRegex
// Some can be useful to construct context, but we can choose not to display them
func SetVerbosity(verbosity types.Verbosity, regexes types.RegexMap) {
	for _, regex := range regexes {
		regex.Verbosity = verbosity
	}
	return
}

func AllRegexes() types.RegexMap {
	IdentsMap.Merge(ViewsMap).Merge(SSTMap).Merge(EventsMap).Merge(StatesMap).Merge(ApplicativeMap).Merge(CustomMap)
	return IdentsMap
}

// general building block wsrep regexes
// It's later used to identify subgroups easier
var (
	groupMethod       = "ssltcp"
	groupNodeIP       = "nodeip"
	groupNodeHash     = "uuid"
	groupUUID         = "uuid" // same value as groupnodehash, because both are used in same context
	groupNodeName     = "nodename"
	groupNodeName2    = "nodename2"
	groupIdx          = "idx"
	groupSeqno        = "seqno"
	groupMembers      = "members"
	groupVersion      = "version"
	groupErrorMD5     = "errormd5"
	regexMembers      = "(?P<" + groupMembers + ">[0-9]{1,2})"
	regexNodeHash     = "(?P<" + groupNodeHash + ">[a-zA-Z0-9-_]+)"
	regexNodeName     = "(?P<" + groupNodeName + `>[a-zA-Z0-9-_\.]+)`
	regexNodeName2    = strings.Replace(regexNodeName, groupNodeName, groupNodeName2, 1)
	regexUUID         = "(?P<" + groupUUID + ">[a-z0-9]+-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]+)" // eg ed97c863-d5c9-11ec-8ab7-671bbd2d70ef
	regexShortUUID    = "(?P<" + groupUUID + ">[a-z0-9]+-[a-z0-9]{4})"                                   // eg ed97c863-8ab7
	regexSeqno        = "(?P<" + groupSeqno + ">[0-9]+)"
	regexNodeIP       = "(?P<" + groupNodeIP + ">[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})"
	regexNodeIPMethod = "(?P<" + groupMethod + ">.+)://" + regexNodeIP + ":[0-9]{1,6}"
	regexIdx          = "(?P<" + groupIdx + ">-?[0-9]{1,2})(\\.-?[0-9])?"
	regexVersion      = "(?P<" + groupVersion + ">(5|8|10|11)\\.[0-9]\\.[0-9]{1,2})"
	regexErrorMD5     = "(?P<" + groupErrorMD5 + ">[a-z0-9]*)"
)

// IsNodeUUID can only try to see if that's an UUID
// functionally, it could also be a "regexNodeHash", but it's indistinguishable from wsrep_node_name
// as it won't have any specific format
func IsNodeUUID(s string) bool {
	b, err := regexp.MatchString(regexUUID, s)
	if err != nil {
		log.Warn().Err(err).Str("input", s).Msg("failed to check if it is an uuid")
		return false
	}
	if b {
		return true
	}
	b, err = regexp.MatchString(regexShortUUID, s)
	if err != nil {
		log.Warn().Err(err).Str("input", s).Msg("failed to check if it is a short uuid")
		return false
	}
	return b
}

func IsNodeIP(s string) bool {
	b, err := regexp.MatchString(regexNodeIP, s)
	if err != nil {
		log.Warn().Err(err).Str("input", s).Msg("failed to check if it is an ip")
		return false
	}
	return b
}
