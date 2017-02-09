package templates

const HostInfo = `# This host
{{ if .ProcPath -}}
# Mongo Executable #######################################################################################
       Path to executable | {{.ProcPath }}
{{ end -}}
# Report On {{.Hostname}} ########################################
{{- if .ProcUserName }}
                     User | {{.ProcUserName }}
{{- end }}
                PID Owner | {{.ProcessName}}
                 Hostname | {{.Hostname}}
                  Version | {{.Version}}
                 Built On | {{.HostOsType}} {{.HostSystemCPUArch}}
                  Started | {{.ProcCreateTime}}
{{- if .DBPath }}
                  Datadir | {{.DBPath}}
{{- end }}
                Processes | {{.ProcProcessCount}}
             Process Type | {{.NodeType}}
{{ if .ReplicaSetName -}}
                  ReplSet | {{.ReplicasetName}}
              Repl Status | 
{{- end -}}
`
