// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
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

package templates

const RunningOps = `
# Running Ops ############################################################################################
Type         Min        Max        Avg
Insert    {{printf "% 8d" .Insert.Min}}   {{printf "% 8d" .Insert.Max}}   {{printf "% 8d" .Insert.Avg}}/{{.SampleRate}}
Query     {{printf "% 8d" .Query.Min}}   {{printf "% 8d" .Query.Max}}   {{printf "% 8d" .Query.Avg}}/{{.SampleRate}}
Update    {{printf "% 8d" .Update.Min}}   {{printf "% 8d" .Update.Max}}   {{printf "% 8d" .Update.Avg}}/{{.SampleRate}}
Delete    {{printf "% 8d" .Delete.Min}}   {{printf "% 8d" .Delete.Max}}   {{printf "% 8d" .Delete.Avg}}/{{.SampleRate}}
GetMore   {{printf "% 8d" .GetMore.Min}}   {{printf "% 8d" .GetMore.Max}}   {{printf "% 8d" .GetMore.Avg}}/{{.SampleRate}}
Command   {{printf "% 8d" .Command.Min}}   {{printf "% 8d" .Command.Max}}   {{printf "% 8d" .Command.Avg}}/{{.SampleRate}}
`
