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
{{ header "Oplog" }}
{{- range $i, $s := . }}
{{- if $i }}
{{ end }}
{{ printf "%25s" "Replica Set" }} | {{ $s.Name }}
{{ printf "%25s" "Primary" }} | {{ $s.Primary }}
{{- with $s.LastElection }}
{{ printf "%25s" "Last Election" }} | {{ . }}{{ with $s.ElectionReason }} ({{ . }}){{ end }}
{{- end }}
{{- range $s.Lines }}
{{ . }}
{{- end }}
{{- with $s.Shortest }}
{{ printf "%25s" "Shortest Window" }} | {{ .Hostname }} ({{ .Running }})
{{- end }}
{{- with $s.Longest }}
{{ printf "%25s" "Longest Window" }} | {{ .Hostname }} ({{ .Running }})
{{- end }}
{{- end }}
`
