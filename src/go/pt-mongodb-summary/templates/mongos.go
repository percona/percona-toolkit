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

const MongosInfo = `
# Mongos #################################################################################################
{{ $padding := 4 }}
{{- $timeWidth := 25 -}}
{{- $hostWidth := .MaxNameLen -}}
{{- $versionWidth := 12 -}}
{{- printf "%-*s" $hostWidth "Host" -}}
{{- printf "%-*s" $padding " " -}}
{{- printf "%-*s" $timeWidth "LastPing" -}}
{{- printf "%-*s" $padding " " -}}
{{- printf "%-*s" $versionWidth "Version" -}}
{{- printf "%-*s" $padding " " -}}Uptime (sec)
{{- if .Instances -}}
{{- range .Instances }}
{{ printf "%-*s" $hostWidth .Name }}
{{- printf "%-*s" $padding " " -}}{{ printf "%-*s" $timeWidth (.LastPing.Format "2006-01-02T15:04:05Z07:00") }}
{{- printf "%-*s" $padding " " -}}{{ printf "%-*s" $versionWidth .Version }}
{{- printf "%-*s" $padding " " -}}{{ printf "%-15d" .UpTime }}
{{- end }}
{{- else }}
                                        no mongos instances found
{{- end }}
`
