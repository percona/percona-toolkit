package templates

const HostInfo = `# This host
# Mongo Executable #######################################################################################
       Path to executable | {{.ProcPath}}
# Report On {{.ThisHostID}} ########################################
                     User | {{.ProcUserName}}
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
