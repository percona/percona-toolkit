package types

import (
	"encoding/json"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

// LogCtx is a context for a given file.
// It is the principal storage of this tool
// Everything relevant will be stored here
type LogCtx struct {
	FilePath               string
	FileType               string
	OwnIPs                 []string
	OwnHashes              []string
	OwnNames               []string
	stateErrorLog          string
	stateRecoveryLog       string
	statePostProcessingLog string
	stateBackupLog         string
	Version                string
	SST                    SST
	MyIdx                  string
	MemberCount            int
	Desynced               bool
	HashToIP               map[string]string
	HashToNodeName         map[string]string
	IPToHostname           map[string]string
	IPToMethod             map[string]string
	IPToNodeName           map[string]string
	minVerbosity           Verbosity
	Conflicts              Conflicts
}

func NewLogCtx() LogCtx {
	return LogCtx{minVerbosity: Debug, HashToIP: map[string]string{}, IPToHostname: map[string]string{}, IPToMethod: map[string]string{}, IPToNodeName: map[string]string{}, HashToNodeName: map[string]string{}}
}

// State will return the wsrep state of the current file type
// That is because for operator related logs, we have every type of files
// Not tracking and differenciating by file types led to confusions in most subcommands
// as it would seem that sometimes mysql is restarting after a crash, while actually
// the operator was simply launching a "wsrep-recover" instance while mysql was still running
func (ctx LogCtx) State() string {
	switch ctx.FileType {
	case "post.processing.log":
		return ctx.statePostProcessingLog
	case "recovery.log":
		return ctx.stateRecoveryLog
	case "backup.log":
		return ctx.stateBackupLog
	case "error.log":
		fallthrough
	default:
		return ctx.stateErrorLog
	}
}

// SetState will double-check if the STATE exists, and also store it on the correct status
func (ctx *LogCtx) SetState(s string) {

	// NON-PRIMARY and RECOVERY are not a real wsrep state, but it's helpful here
	// DONOR and DESYNCED are merged in wsrep, but we are able to distinguish here
	// list at gcs/src/gcs.cpp, gcs_conn_state_str
	if !utils.SliceContains([]string{"SYNCED", "JOINED", "DONOR", "DESYNCED", "JOINER", "PRIMARY", "NON-PRIMARY", "OPEN", "CLOSED", "DESTROYED", "ERROR", "RECOVERY"}, s) {
		return
	}
	//ctx.state[ctx.FileType] = append(ctx.state[ctx.FileType], s)
	switch ctx.FileType {
	case "post.processing.log":
		ctx.statePostProcessingLog = s
	case "recovery.log":
		ctx.stateRecoveryLog = s
	case "backup.log":
		ctx.stateBackupLog = s
	case "error.log":
		fallthrough
	default:
		ctx.stateErrorLog = s
	}
}

func (ctx *LogCtx) HasVisibleEvents(level Verbosity) bool {
	return level >= ctx.minVerbosity
}

func (ctx *LogCtx) IsPrimary() bool {
	return utils.SliceContains([]string{"SYNCED", "DONOR", "DESYNCED", "JOINER", "PRIMARY"}, ctx.State())
}

func (ctx *LogCtx) OwnHostname() string {
	for _, ip := range ctx.OwnIPs {
		if hn, ok := ctx.IPToHostname[ip]; ok {
			return hn
		}
	}
	for _, hash := range ctx.OwnHashes {
		if hn, ok := ctx.IPToHostname[ctx.HashToIP[hash]]; ok {
			return hn
		}
	}
	return ""
}

func (ctx *LogCtx) HashesFromIP(ip string) []string {
	hashes := []string{}
	for hash, ip2 := range ctx.HashToIP {
		if ip == ip2 {
			hashes = append(hashes, hash)
		}
	}
	return hashes
}

func (ctx *LogCtx) HashesFromNodeName(nodename string) []string {
	hashes := []string{}
	for hash, nodename2 := range ctx.HashToNodeName {
		if nodename == nodename2 {
			hashes = append(hashes, hash)
		}
	}
	return hashes
}

func (ctx *LogCtx) IPsFromNodeName(nodename string) []string {
	ips := []string{}
	for ip, nodename2 := range ctx.IPToNodeName {
		if nodename == nodename2 {
			ips = append(ips, ip)
		}
	}
	return ips
}

func (ctx *LogCtx) AllNodeNames() []string {
	nodenames := ctx.OwnNames
	for _, nn := range ctx.HashToNodeName {
		if !utils.SliceContains(nodenames, nn) {
			nodenames = append(nodenames, nn)
		}
	}
	for _, nn := range ctx.IPToNodeName {
		if !utils.SliceContains(nodenames, nn) {
			nodenames = append(nodenames, nn)
		}
	}
	return nodenames
}

// AddOwnName propagates a name into the translation maps using the trusted node's known own hashes and ips
func (ctx *LogCtx) AddOwnName(name string) {
	// used to be a simple "if utils.SliceContains", changed to "is it the last known name?"
	// because somes names/ips come back and forth, we should keep track of that
	name = utils.ShortNodeName(name)
	if len(ctx.OwnNames) > 0 && ctx.OwnNames[len(ctx.OwnNames)-1] == name {
		return
	}
	ctx.OwnNames = append(ctx.OwnNames, name)
	for _, hash := range ctx.OwnHashes {

		ctx.HashToNodeName[hash] = name
	}
	for _, ip := range ctx.OwnIPs {
		ctx.IPToNodeName[ip] = name
	}
}

// AddOwnHash propagates a hash into the translation maps
func (ctx *LogCtx) AddOwnHash(hash string) {
	if utils.SliceContains(ctx.OwnHashes, hash) {
		return
	}
	ctx.OwnHashes = append(ctx.OwnHashes, hash)

	for _, ip := range ctx.OwnIPs {
		ctx.HashToIP[hash] = ip
	}
	for _, name := range ctx.OwnNames {
		ctx.HashToNodeName[hash] = name
	}
}

// AddOwnIP propagates a ip into the translation maps
func (ctx *LogCtx) AddOwnIP(ip string) {
	// see AddOwnName comment
	if len(ctx.OwnIPs) > 0 && ctx.OwnIPs[len(ctx.OwnIPs)-1] == ip {
		return
	}
	ctx.OwnIPs = append(ctx.OwnIPs, ip)
	for _, hash := range ctx.OwnHashes {
		ctx.HashToIP[hash] = ip
	}
	for _, name := range ctx.OwnNames {
		ctx.IPToNodeName[ip] = name
	}
}

// MergeMapsWith will take a slice of contexts and merge every translation maps
// into the base context. It won't touch "local" infos such as "ownNames"
func (base *LogCtx) MergeMapsWith(ctxs []LogCtx) {
	for _, ctx := range ctxs {
		for hash, ip := range ctx.HashToIP {
			base.HashToIP[hash] = ip
		}
		for hash, nodename := range ctx.HashToNodeName {

			base.HashToNodeName[hash] = nodename
		}
		for ip, hostname := range ctx.IPToHostname {
			base.IPToHostname[ip] = hostname
		}
		for ip, nodename := range ctx.IPToNodeName {
			base.IPToNodeName[ip] = nodename
		}
		for ip, method := range ctx.IPToMethod {
			base.IPToMethod[ip] = method
		}
	}
}

// Inherit will fill the local information from given context
// into the base
// It is used when merging, so that we do not start from nothing
// It helps when dealing with many small files
func (base *LogCtx) Inherit(ctx LogCtx) {
	base.OwnHashes = append(ctx.OwnHashes, base.OwnHashes...)
	base.OwnNames = append(ctx.OwnNames, base.OwnNames...)
	base.OwnIPs = append(ctx.OwnIPs, base.OwnIPs...)
	if base.Version == "" {
		base.Version = ctx.Version
	}
	base.MergeMapsWith([]LogCtx{ctx})
}

func (l LogCtx) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		FilePath               string
		FileType               string
		OwnIPs                 []string
		OwnHashes              []string
		OwnNames               []string
		StateErrorLog          string
		StateRecoveryLog       string
		StatePostProcessingLog string
		StateBackupLog         string
		Version                string
		SST                    SST
		MyIdx                  string
		MemberCount            int
		Desynced               bool
		HashToIP               map[string]string
		HashToNodeName         map[string]string
		IPToHostname           map[string]string
		IPToMethod             map[string]string
		IPToNodeName           map[string]string
		MinVerbosity           Verbosity
		Conflicts              Conflicts
	}{
		FilePath:               l.FilePath,
		FileType:               l.FileType,
		OwnIPs:                 l.OwnIPs,
		OwnHashes:              l.OwnHashes,
		StateErrorLog:          l.stateErrorLog,
		StateRecoveryLog:       l.stateRecoveryLog,
		StatePostProcessingLog: l.statePostProcessingLog,
		StateBackupLog:         l.stateBackupLog,
		Version:                l.Version,
		SST:                    l.SST,
		MyIdx:                  l.MyIdx,
		MemberCount:            l.MemberCount,
		Desynced:               l.Desynced,
		HashToIP:               l.HashToIP,
		HashToNodeName:         l.HashToNodeName,
		IPToHostname:           l.IPToHostname,
		IPToMethod:             l.IPToMethod,
		IPToNodeName:           l.IPToNodeName,
		MinVerbosity:           l.minVerbosity,
		Conflicts:              l.Conflicts,
	})
}
