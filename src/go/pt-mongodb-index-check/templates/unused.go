package templates

// {{if $i}},{{end}} adds a comma after the first element.
// When $i == 0 (first element) {{ if $i }} returns false (0)

var Unused = `
Unused indexes 
{{ range . }}
{{ .Spec.Namespace }}, index '{{ .Name }}' with fields { {{- range $i, $val := .Key }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }} }{{ end }}{{ end}}
`
