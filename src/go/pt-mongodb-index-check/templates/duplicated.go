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
# ---- UNIQUE / CONSTRAINT WARNING ----------------------------
{{ range .WithWarning }}
  {{ .Namespace }}
    Prefix:    '{{ .Name }}' { {{- range $i, $v := .Key }}{{if $i}}, {{end}}{{ $v.Key }}:{{ $v.Value }}{{ end -}} }  [UNIQUE]{{ if .HasSizes }}  {{ formatBytes .PrefixSize }}{{ end }}
    Container: '{{ .ContainerName }}' { {{- range $i, $v := .ContainerKey }}{{if $i}}, {{end}}{{ $v.Key }}:{{ $v.Value }}{{ end -}} }{{ if .HasSizes }}  {{ formatBytes .ContainerSize }}{{ end }}
    Reason: {{ .Reason }}
    WARNING: {{ .Warning }}
    Action: {{ .Action }}
{{ end }}{{ end }}
# Summary: {{ len .Standard }} redundant prefix pair(s), {{ len .WithWarning }} with unique/constraint warning(s)
`
