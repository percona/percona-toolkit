package templates

var Analysis = `
# ============================================================
# Unused Index Analysis
# ============================================================
# Observation window: {{ .ObsStart }} to {{ .ObsEnd }} ({{ .ObsDays }} days)
# Indexes analyzed: {{ .TotalAnalyzed }} across {{ .DatabaseCount }} database(s), {{ .CollectionCount }} collection(s)
# Server write rate: ~{{ .WriteRate }} ops/sec
{{ if .SafeToDrop }}
# ---- SAFE TO DROP (high confidence) --------------------------
{{ range .SafeToDrop }}
  {{ .Namespace }}  index '{{ .IndexName }}' { {{- range $i, $val := .IndexKey }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }}{{ end -}} }
    Ops: {{ .AccessOps }} in {{ .AgeDays }} days | Size: {{ formatBytes .IndexSizeBytes }} | Score: {{ printf "%.2f" .Score }}
    Reason: {{ .Reason }}
    Action: db.{{ collName .Namespace }}.dropIndex("{{ .IndexName }}")
{{ end }}{{ end }}{{ if .LikelyUnused }}
# ---- LIKELY UNUSED (review recommended) ----------------------
{{ range .LikelyUnused }}
  {{ .Namespace }}  index '{{ .IndexName }}' { {{- range $i, $val := .IndexKey }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }}{{ end -}} }
    Ops: {{ .AccessOps }} in {{ .AgeDays }} days | Size: {{ formatBytes .IndexSizeBytes }} | Score: {{ printf "%.2f" .Score }}
    Reason: {{ .Reason }}
{{ end }}{{ end }}{{ if .LowUsage }}
# ---- LOW USAGE (non-zero but minimal) ------------------------
{{ range .LowUsage }}
  {{ .Namespace }}  index '{{ .IndexName }}' { {{- range $i, $val := .IndexKey }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }}{{ end -}} }
    Ops: {{ .AccessOps }} in {{ .AgeDays }} days ({{ printf "%.1f" .OpsPerDay }}/day) | Size: {{ formatBytes .IndexSizeBytes }} | Score: {{ printf "%.2f" .Score }}
    Reason: {{ .Reason }}
{{ end }}{{ end }}{{ if .Monitor }}
# ---- MONITOR (insufficient data) -----------------------------
{{ range .Monitor }}
  {{ .Namespace }}  index '{{ .IndexName }}' { {{- range $i, $val := .IndexKey }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }}{{ end -}} }
    Ops: {{ .AccessOps }} in {{ .AgeDays }} days | Size: {{ formatBytes .IndexSizeBytes }} | Score: {{ printf "%.2f" .Score }}
    Reason: {{ .Reason }}
{{ end }}{{ end }}{{ if .Keep }}
# ---- KEEP (constraints / special) ----------------------------
{{ range .Keep }}
  {{ .Namespace }}  index '{{ .IndexName }}' { {{- range $i, $val := .IndexKey }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }}{{ end -}} }{{ tagFor . }}
    Ops: {{ .AccessOps }} in {{ .AgeDays }} days | Kept: {{ .Reason }}
{{ end }}{{ end }}
# Summary: {{ .SafeToDropCount }} safe to drop{{ if gt .SafeToDropSavings 0 }} (saving ~{{ formatBytes .SafeToDropSavings }}){{ end }}, {{ .LikelyUnusedCount }} likely unused, {{ .LowUsageCount }} low usage, {{ .MonitorCount }} monitoring, {{ .KeepCount }} kept (constraints)
`
