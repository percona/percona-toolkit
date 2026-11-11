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

const CmdlineArgs = `
{{ if . -}}
# Command line arguments
{{ range .CmdlineArgs -}} {{-  . }} {{ end }}
{{- if .ParsedConfig }}
# Active Configuration
{{- with .ParsedConfig.Parsed }}
{{- if .Config }}
             Config File | {{.Config}}
{{- end }}
{{- if .Net.Port }}
                    Port | {{.Net.Port}}
{{- end }}
{{- if .Net.BindIP }}
                 Bind IP | {{.Net.BindIP}}
{{- end }}
{{- if .Net.MaxIncomingConnections }}
   Max Incoming Conns    | {{.Net.MaxIncomingConnections}}
{{- end }}
{{- if .Net.SSL.Mode }}
                     SSL | {{.Net.SSL.Mode}}
{{- end }}
{{- if .Storage.DbPath }}
               Data Path | {{.Storage.DbPath}}
{{- end }}
{{- if .Storage.Engine }}
          Storage Engine | {{.Storage.Engine}}
{{- end }}
{{- if .Storage.WiredTiger.EngineConfig.CacheSizeGB }}
       WT Cache Size     | {{.Storage.WiredTiger.EngineConfig.CacheSizeGB}} GB
{{- end }}
{{- if .Replication.ReplSet }}
                 ReplSet | {{.Replication.ReplSet}}
{{- end }}
{{- if .Security.Authorization }}
           Authorization | {{.Security.Authorization}}
{{- end }}
{{- if .Security.KeyFile }}
                Key File | {{.Security.KeyFile}}
{{- end }}
{{- if .SystemLog.Path }}
                 Log Path | {{.SystemLog.Path}}
{{- end }}
{{- if .SystemLog.LogAppend }}
              Log Append | true
{{- end }}
{{- if .OperationProfiling.Mode }}
        Profiling Mode   | {{.OperationProfiling.Mode}}
{{- end }}
{{- if .OperationProfiling.SlowOpThresholdMs }}
   Slow Op Threshold     | {{.OperationProfiling.SlowOpThresholdMs}} ms
{{- end }}
{{- end }}
{{- end }}
{{- end }}
`
