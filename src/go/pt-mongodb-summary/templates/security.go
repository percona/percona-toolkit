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

const Security = `
{{ header "Security" }}
{{- if not .IsArbiter }}
{{- if .CountsReadable }}
Users  : {{ .Users }}
Roles  : {{ .Roles }}
{{- else if .CountsDenied }}
Users  : not readable with this login (needs find on admin.system.users)
Roles  : not readable with this login
{{- else }}
Users  : not collected{{ with .CountsReason }} ({{ . }}){{ end }}
Roles  : not collected{{ with .CountsReason }} ({{ . }}){{ end }}
{{- end }}
{{- end }}
Auth   : {{ .Auth }}
SSL    : {{ .SSL }}
Port   : {{ .Port }}
Bind IP: {{ .BindIP }}
{{- range .WarningMsgs }}
{{ . }}
{{- end }}
`
