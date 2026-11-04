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
{{ header "Running Ops" }}
Per second over {{ dur .Elapsed }} of sampling; "Since start" = average over {{ dur .Uptime }} of uptime
{{- with .Partial }}
{{ . }}
{{- end }}
Type           Min/s       Max/s       Avg/s   Since start/day
{{- range .Rates.Rows }}
{{ printf "%-8s%12s%12s%12s%18s" .Name (rate .Min) (rate .Max) (rate .Avg) (rate .SinceStartPerDay) }}
{{- end }}
{{- with .ReplRates }}
Replicated (oplog entries applied; counts documents)
{{- range .ReplRows }}
{{ printf "%-8s%12s%12s%12s%18s" .Name (rate .Min) (rate .Max) (rate .Avg) (rate .SinceStartPerDay) }}
{{- end }}
{{- end }}
`
