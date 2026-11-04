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

const OSChecks = `
{{ header "OS & Production Checks" }}
{{- with .OSSummary }}
                       OS | {{ . }}
{{- end }}
{{- with .KernelVersion }}
                   Kernel | {{ . }}
{{- end }}
{{- with .CPUSummary }}
                CPU cores | {{ . }}
{{- end }}
{{- with .RAMSummary }}
                      RAM | {{ . }}
{{- end }}
{{- with .NUMASummary }}
                     NUMA | {{ . }}{{ with $.NUMAWarning }}  [WARNING: {{ . }}]{{ end }}
{{- end }}
{{- if gt .MaxOpenFiles 0 }}
         Open files limit | {{ .MaxOpenFiles }}{{ with .OpenFilesWarning }}  [WARNING: {{ . }}]{{ end }}
{{- end }}
{{- with .Local }}
         vm.max_map_count | {{ .MaxMapCountText }}{{ with .MaxMapCountWarning }}  [WARNING: {{ . }}]{{ end }}
   Max processes (mongod) | {{ .MaxProcessesText }}{{ with .MaxProcessesWarning }}  [WARNING: {{ . }}]{{ end }}
     Tasks limit (cgroup) | {{ .TasksLimitText }}{{ with .TasksLimitWarning }}  [WARNING: {{ . }}]{{ end }}
{{- else }}
{{- with .LocalSkipReason }}
             Local checks | skipped: {{ . }}
{{- end }}
{{- end }}
{{- with .StartupWarningsSummary }}
         Startup warnings | {{ . }}
{{- end }}
{{- range .StartupWarnings }}
  - {{ .Text }}
{{- end }}
`
