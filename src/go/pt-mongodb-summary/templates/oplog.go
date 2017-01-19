package templates

const Oplog = `
# Oplog ##################################################################################################
Oplog Size     {{.Size}} Mb
Oplog Used     {{.UsedMB}} Mb
Oplog Length   {{.Running}}
Last Election  {{.ElectionTime}}
`
