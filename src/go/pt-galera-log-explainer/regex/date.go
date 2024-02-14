package regex

import (
	"fmt"
	"strconv"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/rs/zerolog/log"
)

// 5.5 date : 151027  6:02:49
// 5.6 date : 2019-07-17 07:16:37
//5.7 date : 2019-07-17T15:16:37.123456Z
//5.7 date : 2019-07-17T15:16:37.123456+01:00
// 10.3 date: 2019-07-15  7:32:25
var DateLayouts = []string{
	"2006-01-02T15:04:05.000000Z",      // 5.7
	"2006-01-02T15:04:05.000000-07:00", // 5.7
	"2006-01-02T15:04:05Z",             // found in some crashes
	"060102 15:04:05",                  // 5.5
	"2006-01-02 15:04:05",              // 5.6
	"2006-01-02  15:04:05",             // 10.3, yes the extra space is needed
	"2006/01/02 15:04:05",              // sometimes found in socat errors
}

// BetweenDateRegex generate a regex to filter mysql error log dates to just get
// events between 2 dates
// Currently limited to filter by day to produce "short" regexes. Finer events will be filtered later in code
// Trying to filter hours, minutes using regexes would produce regexes even harder to read
// while not really adding huge benefit as we do not expect so many events of interets
func BetweenDateRegex(since *time.Time, skipLeadingCircumflex bool) string {
	/*
		"2006-01-02
		"2006-01-0[3-9]
		"2006-01-[1-9][0-9]
		"2006-0[2-9]-[0-9]{2}
		"2006-[1-9][0-9]-[0-9]{2}
		"200[7-9]-[0-9]{2}-[0-9]{2}
		"20[1-9][0-9]-[0-9]{2}-[0-9]{2}
	*/

	separator := "|^"
	if skipLeadingCircumflex {
		separator = "|"
	}

	regexConstructor := []struct {
		unit      int
		unitToStr string
	}{
		{
			unit:      since.Day(),
			unitToStr: fmt.Sprintf("%02d", since.Day()),
		},
		{
			unit:      int(since.Month()),
			unitToStr: fmt.Sprintf("%02d", since.Month()),
		},
		{
			unit:      since.Year(),
			unitToStr: fmt.Sprintf("%d", since.Year())[2:],
		},
	}
	s := ""
	for _, layout := range []string{"2006-01-02", "060102"} {
		// base complete date
		lastTransformed := since.Format(layout)
		s += separator + lastTransformed

		for _, construct := range regexConstructor {
			if construct.unit != 9 {
				s += separator + utils.StringsReplaceReversed(lastTransformed, construct.unitToStr, string(construct.unitToStr[0])+"["+strconv.Itoa(construct.unit%10+1)+"-9]", 1)
			}
			// %1000 here is to cover the transformation of 2022 => 22
			s += separator + utils.StringsReplaceReversed(lastTransformed, construct.unitToStr, "["+strconv.Itoa((construct.unit%1000/10)+1)+"-9][0-9]", 1)

			lastTransformed = utils.StringsReplaceReversed(lastTransformed, construct.unitToStr, "[0-9][0-9]", 1)

		}
	}
	s += ")"
	return "(" + s[1:]
}

// basically capturing anything that does not have a date
// needed, else we would miss some logs, like wsrep recovery
func NoDatesRegex(skipLeadingCircumflex bool) string {
	//return "((?![0-9]{4}-[0-9]{2}-[0-9]{2})|(?![0-9]{6}))"
	if skipLeadingCircumflex {
		return "(?![0-9]{4})"
	}
	return "^(?![0-9]{4})"
}

func SearchDateFromLog(logline string) (time.Time, string, bool) {
	if logline[:len(types.OperatorLogPrefix)] == types.OperatorLogPrefix {
		logline = logline[len(types.OperatorLogPrefix):]
	}
	for _, layout := range DateLayouts {
		if len(logline) < len(layout) {
			continue
		}
		t, err := time.Parse(layout, logline[:len(layout)])
		if err == nil {
			return t, layout, true
		}
	}
	log.Debug().Str("log", logline).Msg("could not find date from log")
	return time.Time{}, "", false
}
