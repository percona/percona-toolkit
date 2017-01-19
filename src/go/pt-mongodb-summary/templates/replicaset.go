package templates

const Replicas = `
# Instances ##############################################################################################
ID    Host                         Type                                 ReplSet             Engine
{{- if . -}}
{{- range . }} 
{{printf "% 3d" .Id}} {{printf "%-30s" .Name}} {{printf "%-30s" .StateStr}} {{printf "%10s" .Set }}  {{printf "%20s" .StorageEngine.Name -}}
{{end}}
{{else}}																		  
                                          no replica sets found
{{end}}
`
