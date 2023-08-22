package templates

const CmdlineArgs = `
{{ if . }}
# Command line arguments
{{ range .CmdlineArgs -}} {{-  . }} {{ end }}
{{- end }}
`
