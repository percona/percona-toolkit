package types

import (
	"encoding/json"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

// LogCtx is the main context storage for a node.
// It is the principal storage of this tool, this is the source of truth to merge logs and take decisions
// It is stored along wih each single log line we matched, and copied for each new log line.
// It is NOT meant to be used as a singleton by pointer, it must keep its original state for each log lines
// If not, every informaiton would be overwritten (states, sst, version, membercount, ...) and we would not be able to give the history of changes
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

	// SSTs where key is donor name, as it will always be known.
	// is meant to be shared with a deep copy, there's no sense to share the pointer
	// because it is meant to store a state at a specific time
	SSTs         map[string]SST
	MyIdx        string
	MemberCount  int
	Desynced     bool
	minVerbosity Verbosity
	Conflicts    Conflicts
}

func NewLogCtx() LogCtx {
	ctx := LogCtx{minVerbosity: Debug}
	ctx.InitMaps()
	return ctx
}

func (ctx *LogCtx) InitMaps() {
	ctx.SSTs = map[string]SST{}
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

// AddOwnName propagates a name into the translation maps using the trusted node's known own hashes and ips
func (ctx *LogCtx) AddOwnName(name string, date time.Time) {
	// used to be a simple "if utils.SliceContains", changed to "is it the last known name?"
	// because somes names/ips come back and forth, we should keep track of that
	name = utils.ShortNodeName(name)
	if len(ctx.OwnNames) > 0 && ctx.OwnNames[len(ctx.OwnNames)-1] == name {
		return
	}
	ctx.OwnNames = append(ctx.OwnNames, name)
	for _, hash := range ctx.OwnHashes {
		translate.AddHashToNodeName(hash, name, date)
	}
	for _, ip := range ctx.OwnIPs {
		translate.AddIPToNodeName(ip, name, date)
	}
}

// AddOwnHash propagates a hash into the translation maps
func (ctx *LogCtx) AddOwnHash(hash string, date time.Time) {
	if utils.SliceContains(ctx.OwnHashes, hash) {
		return
	}
	ctx.OwnHashes = append(ctx.OwnHashes, hash)

	for _, ip := range ctx.OwnIPs {
		translate.AddHashToIP(hash, ip, date)
	}
	for _, name := range ctx.OwnNames {
		translate.AddHashToNodeName(hash, name, date)
	}
}

// AddOwnIP propagates a ip into the translation maps
func (ctx *LogCtx) AddOwnIP(ip string, date time.Time) {
	// see AddOwnName comment
	if len(ctx.OwnIPs) > 0 && ctx.OwnIPs[len(ctx.OwnIPs)-1] == ip {
		return
	}
	ctx.OwnIPs = append(ctx.OwnIPs, ip)
	for _, name := range ctx.OwnNames {
		translate.AddIPToNodeName(ip, name, date)
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
	base.Conflicts = append(ctx.Conflicts, base.Conflicts...)
}

func (ctx *LogCtx) SetSSTTypeMaybe(ssttype string) {
	for key, sst := range ctx.SSTs {
		if len(ctx.SSTs) == 1 || (ctx.State() == "DONOR" && utils.SliceContains(ctx.OwnNames, key)) || (ctx.State() == "JOINER" && utils.SliceContains(ctx.OwnNames, sst.Joiner)) {
			sst.Type = ssttype
			ctx.SSTs[key] = sst
			return
		}
	}
}

func (ctx *LogCtx) ConfirmSSTMetadata(shiftTimestamp time.Time) {
	if ctx.State() != "DONOR" && ctx.State() != "JOINER" {
		return
	}
	for key, sst := range ctx.SSTs {
		if sst.MustHaveHappenedLocally(shiftTimestamp) {
			if ctx.State() == "DONOR" {
				ctx.AddOwnName(key, shiftTimestamp)
			}
			if ctx.State() == "JOINER" {
				ctx.AddOwnName(sst.Joiner, shiftTimestamp)
			}
		}
	}

	return
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
		SSTs                   map[string]SST
		MyIdx                  string
		MemberCount            int
		Desynced               bool
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
		SSTs:                   l.SSTs,
		MyIdx:                  l.MyIdx,
		MemberCount:            l.MemberCount,
		Desynced:               l.Desynced,
		MinVerbosity:           l.minVerbosity,
		Conflicts:              l.Conflicts,
	})
}
