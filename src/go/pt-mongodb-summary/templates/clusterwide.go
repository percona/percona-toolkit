package templates

const Clusterwide = `
# Cluster wide ###########################################################################################
            Databases: {{.TotalDBsCount}}
          Collections: {{.TotalCollectionsCount}}
  Sharded Collections: {{.ShardedColsCount}}
Unsharded Collections: {{.UnshardedColsCount}}
    Sharded Data Size: {{.ShardedDataSizeScaled}} {{.ShardedDataSizeScale}}          
  Unsharded Data Size: {{.UnshardedDataSizeScaled}} {{.UnshardedDataSizeScale}}`
