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

const Oplog = `
# Oplog ##################################################################################################
{{- range .Nodes }}
  {{printf "%-40s" .Hostname}}  {{printf "%8d" .UsedMB}} MB used / {{printf "%8d" .Size}} MB  Length: {{.Running}}{{if not .ElectionTime.IsZero}}  Election: {{.ElectionTime.Format "2006-01-02T15:04:05Z"}}{{end}}
{{- end }}
  Min Oplog Host | {{.MinHost}}
  Max Oplog Host | {{.MaxHost}}
`
