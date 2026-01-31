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
	"regexp"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/pkg/errors"
)

var CustomMap = types.RegexMap{}

func AddCustomRegexes(regexes map[string]string) error {
	for regexstring, output := range regexes {
		r, err := regexp.Compile(regexstring)
		if err != nil {
			return errors.Wrap(err, "failed to add custom regex")
		}

		lr := &types.LogRegex{Regex: r, Type: types.CustomRegexType}

		if output == "" {
			// capture and print everything that matched, instead of a static message
			lr.InternalRegex, err = regexp.Compile("(?P<all>" + regexstring + ")")
			if err != nil {
				return errors.Wrap(err, "failed to add custom regex: failed to generate dynamic output")
			}

			lr.Handler = func(submatch map[string]string, ctx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
				return ctx, types.SimpleDisplayer(utils.Paint(utils.MagentaText, submatch["all"]))
			}

		} else {
			lr.Handler = func(_ map[string]string, ctx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
				return ctx, types.SimpleDisplayer(utils.Paint(utils.MagentaText, output))
			}
		}

		CustomMap[regexstring] = lr
	}
	return nil
}
