package templates

const Replicas = `
# Instances ##############################################################################################
  PID    Host                         Type                      ReplSet                   Engine
{{- if . -}}
{{- range . }} 
{{printf "% 6d" .ID}} {{printf "%-30s" .Name}} {{printf "%-25s" .StateStr}} {{ if .Set }}{{printf "%-10s" .Set }}{{else}}-         {{end}}  {{printf "%20s" .StorageEngine.Name -}}
{{end}}
{{else}}																		  
                                          no replica sets found
{{end}}
`
