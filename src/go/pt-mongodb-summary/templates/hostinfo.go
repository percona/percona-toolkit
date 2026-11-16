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

const HostInfo = `# This host
{{ if .ProcPath -}}
# Mongo Executable #######################################################################################
       Path to executable | {{.ProcPath }}
{{ end -}}
# Report On {{.Hostname}} ########################################
{{- if .ProcUserName }}
                     User | {{.ProcUserName }}
{{- end }}
{{- if .ProcessName }}
                PID Owner | {{.ProcessName}}
{{- end }}
                 Hostname | {{.Hostname}}
{{- if .Version }}
                  Version | {{.Version}}
{{- end }}
{{- if or .HostOsType .HostSystemCPUArch }}
                 Built On | {{.HostOsType}} {{.HostSystemCPUArch}}
{{- end }}
{{- if not .ProcCreateTime.IsZero }}
                  Started | {{.ProcCreateTime}}
{{- end }}
{{- if .DBPath }}
                  Datadir | {{.DBPath}}
{{- end }}
                Processes | {{.ProcProcessCount}}
             Process Type | {{.NodeType}}
{{- if .ReplicasetName }}
                  ReplSet | {{.ReplicasetName}}
              Repl Status |
{{- end }}
{{- if .IsArbiter }}

# Arbiter ################################################################################################
This node is a replica-set ARBITER: it holds no data and does not accept user logins,
so user/role counts, mongos and oplog details are not collected from it.
{{- end -}}
`
