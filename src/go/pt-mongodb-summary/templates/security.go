package templates

const Security = `
# Security ###############################################################################################
Users  : {{.Users}}
Roles  : {{.Roles}}
Auth   : {{.Auth}}
SSL    : {{.SSL}}
Port   : {{.Port}}
Bind IP: {{.BindIP}}
{{- if .WarningMsgs -}}
{{- range .WarningMsgs }} 
{{ . }}
{{end}}
{{end }}
  `
