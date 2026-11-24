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

const Connections = `
{{ header "Connections & Profiling" }}
{{- with .Connections }}
                  Current | {{ .Current }}
                Available | {{ .Available }}
                    Limit | {{ .Limit }} ({{ .LimitSource }})
{{- if .MaxIncomingConnections }}
   maxIncomingConnections | {{ .MaxIncomingConnections }}
{{- else if $.StartupOptions }}
   maxIncomingConnections | not set
{{- end }}
{{- if .Active }}
                   Active | {{ .Active }}
{{- end }}
{{- if .Rejected }}
                 Rejected | {{ .Rejected }}
{{- end }}
            Total Created | {{ .TotalCreated }}{{ if .TotalCreatedWrapped }} (wrapped){{ end }}
{{- end }}
{{- with .Profiling }}
        Slow Op Threshold | {{ .SlowMs }} ms{{ if .StartupDiffers }} (startup: {{ .StartupSlowMs }} ms){{ end }}
              Sample Rate | {{ .SampleRate }}
{{- if .AdminFilter }}
           Filter (admin) | {{ .AdminFilter }}
                          | slowms and sampleRate do not apply while a filter is set
{{- end }}
{{- end }}
`
