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

const CmdlineArgs = `
{{ if . -}}
# Command line arguments
{{ range .CmdlineArgs -}} {{-  . }} {{ end }}
{{- if .ParsedConfig }}
# Active Configuration
{{- with .ParsedConfig.Parsed }}
{{- if .Net.Port }}
                    Port | {{.Net.Port}}
{{- end }}
{{- if .Net.BindIP }}
                 Bind IP | {{.Net.BindIP}}
{{- end }}
{{- if .Net.SSL.Mode }}
                     SSL | {{.Net.SSL.Mode}}
{{- end }}
{{- if .Storage.DbPath }}
              Data Path   | {{.Storage.DbPath}}
{{- end }}
{{- if .Storage.Engine }}
          Storage Engine  | {{.Storage.Engine}}
{{- end }}
{{- if .Replication.ReplSet }}
                 ReplSet  | {{.Replication.ReplSet}}
{{- end }}
{{- if .Security.Authorization }}
           Authorization  | {{.Security.Authorization}}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
`
