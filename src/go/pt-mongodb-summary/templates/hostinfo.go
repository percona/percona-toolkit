package templates

const HostInfo = `# This host
# Mongo Executable #############################################################################
       Path to executable | {{.ProcPath}}
              Has symbols | No
# Report On {{.ThisHostID}} ########################################
                     User | {{.ProcUserName}}
                PID Owner | {{.ProcessName}}
                     Time | {{.ProcCreateTime}}
                 Hostname | {{.Hostname}}
                  Version | {{.Version}}
                 Built On | {{.HostOsType}} {{.HostSystemCPUArch}}
                  Started | {{.ProcCreateTime}}
                Databases | {{.HostDatabases}}
              Collections | {{.HostCollections}}
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
