package templates

const Clusterwide = `
# Cluster wide ###########################################################################################
            Databases: {{.TotalDBsCount}}
          Collections: {{.TotalCollectionsCount}}
  Sharded Collections: {{.ShardedColsCount}}
Unsharded Collections: {{.UnshardedColsCount}}
    Sharded Data Size: {{.ShardedDataSizeScaled}} {{.ShardedDataSizeScale}}          
  Unsharded Data Size: {{.UnshardedDataSizeScaled}} {{.UnshardedDataSizeScale}}
{{- if .Chunks }}
          ###  Chunks: 
{{- range .Chunks }}
{{- if .ID }}
               {{ printf "%5d" .Count }} : {{ printf "%-30s" .ID}}
{{- end }}
{{- end }}
{{- end -}}
`
