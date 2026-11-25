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
	"fmt"
	"regexp"
	"strconv"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
	"github.com/rs/zerolog/log"
)

var jsonDateRE = regexp.MustCompile(`"\$date"\s*:\s*\{\s*"\$numberLong"\s*:\s*"([0-9]+)"\s*\}`)
var jsonDateREISO = regexp.MustCompile(`"\$date"\s*:\s*"([^"]+)"`)

// DateLayouts cover common mongod log timestamp prefixes (legacy text format).
var DateLayouts = []string{
	"2006-01-02T15:04:05.000000Z07:00",
	"2006-01-02T15:04:05.000000Z",
	"2006-01-02T15:04:05.000Z07:00",
	"2006-01-02T15:04:05.000Z",
	"2006-01-02T15:04:05Z07:00",
	"2006-01-02T15:04:05Z",
	"2006-01-02T15:04:05.000000+0000",
	"2006-01-02T15:04:05.000+0000",
	"2006-01-02T15:04:05.000000-0700",
	"2006-01-02T15:04:05.000-0700",
}

func BetweenDateRegex(since *time.Time, skipLeadingCircumflex bool) string {
	separator := "|^"
	if skipLeadingCircumflex {
		separator = "|"
	}
	regexConstructor := []struct {
		unit      int
		unitToStr string
	}{
		{unit: since.Day(), unitToStr: fmt.Sprintf("%02d", since.Day())},
		{unit: int(since.Month()), unitToStr: fmt.Sprintf("%02d", since.Month())},
		{unit: since.Year(), unitToStr: fmt.Sprintf("%d", since.Year())[2:]},
	}
	s := ""
	for _, layout := range []string{"2006-01-02", "060102"} {
		lastTransformed := since.Format(layout)
		s += separator + lastTransformed
		for _, construct := range regexConstructor {
			if construct.unit != 9 {
				s += separator + utils.StringsReplaceReversed(lastTransformed, construct.unitToStr, string(construct.unitToStr[0])+"["+strconv.Itoa(construct.unit%10+1)+"-9]", 1)
			}
			s += separator + utils.StringsReplaceReversed(lastTransformed, construct.unitToStr, "["+strconv.Itoa((construct.unit%1000/10)+1)+"-9][0-9]", 1)
			lastTransformed = utils.StringsReplaceReversed(lastTransformed, construct.unitToStr, "[0-9][0-9]", 1)
		}
	}
	s += ")"
	return "(" + s[1:]
}

func NoDatesRegex(skipLeadingCircumflex bool) string {
	if skipLeadingCircumflex {
		return "(?![0-9]{4})"
	}
	return "^(?![0-9]{4})"
}

func SearchDateFromLog(logline string) (time.Time, string, bool) {
	if m := jsonDateREISO.FindStringSubmatch(logline); len(m) > 1 {
		raw := m[1]
		for _, layout := range DateLayouts {
			if len(raw) < 10 {
				break
			}
			if t, err := time.Parse(layout, raw); err == nil {
				return t, layout, true
			}
		}
		if t, err := time.Parse(time.RFC3339Nano, raw); err == nil {
			return t, time.RFC3339Nano, true
		}
		if t, err := time.Parse(time.RFC3339, raw); err == nil {
			return t, time.RFC3339, true
		}
	}
	if m := jsonDateRE.FindStringSubmatch(logline); len(m) > 1 {
		ms, err := strconv.ParseInt(m[1], 10, 64)
		if err == nil {
			sec := ms / 1000
			nsec := (ms % 1000) * 1e6
			t := time.Unix(sec, nsec).UTC()
			return t, "epoch_ms", true
		}
	}
	for _, layout := range DateLayouts {
		if len(logline) < len(layout) {
			continue
		}
		prefix := logline
		if len(prefix) > len(layout) {
			prefix = logline[:len(layout)]
		}
		t, err := time.Parse(layout, prefix)
		if err == nil {
			return t, layout, true
		}
	}
	log.Debug().Str("log", logline).Msg("could not find date from log")
	return time.Time{}, "", false
}
