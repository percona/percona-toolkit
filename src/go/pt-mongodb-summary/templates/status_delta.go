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

const StatusDelta = `
{{ if . -}}
# Opcount Deltas ({{.Duration}}) ########################################################################
  Type       Per Second         Per Day
  Insert   {{printf "%10.2f" .Insert.PerSec}}  {{printf "%14.0f" .Insert.PerDay}}
  Query    {{printf "%10.2f" .Query.PerSec}}  {{printf "%14.0f" .Query.PerDay}}
  Update   {{printf "%10.2f" .Update.PerSec}}  {{printf "%14.0f" .Update.PerDay}}
  Delete   {{printf "%10.2f" .Delete.PerSec}}  {{printf "%14.0f" .Delete.PerDay}}
  GetMore  {{printf "%10.2f" .GetMore.PerSec}}  {{printf "%14.0f" .GetMore.PerDay}}
  Command  {{printf "%10.2f" .Command.PerSec}}  {{printf "%14.0f" .Command.PerDay}}
{{- end }}
`
