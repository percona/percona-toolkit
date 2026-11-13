// This program is copyright 2022-2026 Percona LLC and/or its affiliates.
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

// Duplicated is the sectioned text template for the duplicate prefix index
// report. It is rendered by renderDuplicateReport in main.go which supplies
// a duplicateReportData value and registers formatBytes / collName helpers.

var Duplicated = `
# ============================================================
# Duplicate Prefix Index Report
# ============================================================
# Pairs found: {{ .TotalPairs }} across {{ .DatabaseCount }} database(s), {{ .CollectionCount }} collection(s)
{{ if eq .TotalPairs 0 }}
# No duplicate prefix indexes detected.
{{ end }}{{ if .Standard }}
# ---- REDUNDANT PREFIX (shorter index is candidate to drop) ---
{{ range .Standard }}
  {{ .Namespace }}
    Prefix:    '{{ .Name }}' { {{- range $i, $v := .Key }}{{if $i}}, {{end}}{{ $v.Key }}:{{ $v.Value }}{{ end -}} }{{ if .HasSizes }}  {{ formatBytes .PrefixSize }}{{ end }}
    Container: '{{ .ContainerName }}' { {{- range $i, $v := .ContainerKey }}{{if $i}}, {{end}}{{ $v.Key }}:{{ $v.Value }}{{ end -}} }{{ if .HasSizes }}  {{ formatBytes .ContainerSize }}{{ end }}
    Reason: {{ .Reason }}
    Action: {{ .Action }}
{{ end }}{{ end }}{{ if .WithWarning }}
# ---- PREFIX ENFORCES A CONSTRAINT (keep it) ------------------
{{ range .WithWarning }}
  {{ .Namespace }}
    Prefix:    '{{ .Name }}' { {{- range $i, $v := .Key }}{{if $i}}, {{end}}{{ $v.Key }}:{{ $v.Value }}{{ end -}} }{{ with .Tag }}  {{ . }}{{ end }}{{ if .HasSizes }}  {{ formatBytes .PrefixSize }}{{ end }}
    Container: '{{ .ContainerName }}' { {{- range $i, $v := .ContainerKey }}{{if $i}}, {{end}}{{ $v.Key }}:{{ $v.Value }}{{ end -}} }{{ if .HasSizes }}  {{ formatBytes .ContainerSize }}{{ end }}
    WARNING: {{ .Warning }}
{{ end }}{{ end }}{{ if .Skipped }}
# ---- NOT REPORTED (key prefix, but index options differ) -----
{{ range .Skipped }}
  {{ .Namespace }}  '{{ .Name }}' is a key prefix of '{{ .ContainerName }}', but {{ .Reason }}
{{- end }}
{{ end }}
# Summary: {{ len .Standard }} redundant prefix pair(s), {{ len .WithWarning }} pair(s) kept for a constraint
`
