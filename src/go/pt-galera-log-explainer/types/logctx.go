package types

import (
	"encoding/json"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

// LogCtx is the main context storage for a node.
// It is the principal storage of this tool, this is the source of truth to merge logs and take decisions
// It is stored along with each single log line we matched, and copied for each new log line.
// It is NOT meant to be used as a singleton by pointer, it must keep its original state for each log lines
// If not, every information would be overwritten (states, sst, version, membercount, ...) and we would not be able to give the history of changes
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
	logCtx := LogCtx{minVerbosity: Debug}
	logCtx.InitMaps()
	return logCtx
}

func (logCtx *LogCtx) InitMaps() {
	logCtx.SSTs = map[string]SST{}
}

// State will return the wsrep state of the current file type
// That is because for operator related logs, we have every type of files
// Not tracking and differentiating by file types led to confusions in most subcommands
// as it would seem that sometimes mysql is restarting after a crash, while actually
// the operator was simply launching a "wsrep-recover" instance while mysql was still running
func (logCtx LogCtx) State() string {
	switch logCtx.FileType {
	case "post.processing.log":
		return logCtx.statePostProcessingLog
	case "recovery.log":
		return logCtx.stateRecoveryLog
	case "backup.log":
		return logCtx.stateBackupLog
	case "error.log":
		fallthrough
	default:
		return logCtx.stateErrorLog
	}
}

// SetState will double-check if the STATE exists, and also store it on the correct status
func (logCtx *LogCtx) SetState(s string) {

	// NON-PRIMARY and RECOVERY are not a real wsrep state, but it's helpful here
	// DONOR and DESYNCED are merged in wsrep, but we are able to distinguish here
	// list at gcs/src/gcs.cpp, gcs_conn_state_str
	if !utils.SliceContains([]string{"SYNCED", "JOINED", "DONOR", "DESYNCED", "JOINER", "PRIMARY", "NON-PRIMARY", "OPEN", "CLOSED", "DESTROYED", "ERROR", "RECOVERY"}, s) {
		return
	}
	switch logCtx.FileType {
	case "post.processing.log":
		logCtx.statePostProcessingLog = s
	case "recovery.log":
		logCtx.stateRecoveryLog = s
	case "backup.log":
		logCtx.stateBackupLog = s
	case "error.log":
		fallthrough
	default:
		logCtx.stateErrorLog = s
	}
}

func (logCtx *LogCtx) HasVisibleEvents(level Verbosity) bool {
	return level >= logCtx.minVerbosity
}

func (logCtx *LogCtx) IsPrimary() bool {
	return utils.SliceContains([]string{"SYNCED", "DONOR", "DESYNCED", "JOINER", "PRIMARY"}, logCtx.State())
}

// AddOwnName propagates a name into the translation maps using the trusted node's known own hashes and ips
func (logCtx *LogCtx) AddOwnName(name string, date time.Time) {
	// used to be a simple "if utils.SliceContains", changed to "is it the last known name?"
	// because some names/ips come back and forth, we should keep track of that
	name = utils.ShortNodeName(name)
	if len(logCtx.OwnNames) > 0 && logCtx.OwnNames[len(logCtx.OwnNames)-1] == name {
		return
	}
	logCtx.OwnNames = append(logCtx.OwnNames, name)
	for _, hash := range logCtx.OwnHashes {
		translate.AddHashToNodeName(hash, name, date)
	}
	for _, ip := range logCtx.OwnIPs {
		translate.AddIPToNodeName(ip, name, date)
	}
}

// AddOwnHash propagates a hash into the translation maps
func (logCtx *LogCtx) AddOwnHash(hash string, date time.Time) {
	if utils.SliceContains(logCtx.OwnHashes, hash) {
		return
	}
	logCtx.OwnHashes = append(logCtx.OwnHashes, hash)

	for _, ip := range logCtx.OwnIPs {
		translate.AddHashToIP(hash, ip, date)
	}
	for _, name := range logCtx.OwnNames {
		translate.AddHashToNodeName(hash, name, date)
	}
}

// AddOwnIP propagates a ip into the translation maps
func (logCtx *LogCtx) AddOwnIP(ip string, date time.Time) {
	// see AddOwnName comment
	if len(logCtx.OwnIPs) > 0 && logCtx.OwnIPs[len(logCtx.OwnIPs)-1] == ip {
		return
	}
	logCtx.OwnIPs = append(logCtx.OwnIPs, ip)
	for _, name := range logCtx.OwnNames {
		translate.AddIPToNodeName(ip, name, date)
	}
}

// Inherit will fill the local information from given context
// into the base
// It is used when merging, so that we do not start from nothing
// It helps when dealing with many small files
func (base *LogCtx) Inherit(logCtx LogCtx) {
	base.OwnHashes = append(logCtx.OwnHashes, base.OwnHashes...)
	base.OwnNames = append(logCtx.OwnNames, base.OwnNames...)
	base.OwnIPs = append(logCtx.OwnIPs, base.OwnIPs...)
	if base.Version == "" {
		base.Version = logCtx.Version
	}
	base.Conflicts = append(logCtx.Conflicts, base.Conflicts...)
}

func (logCtx *LogCtx) SetSSTTypeMaybe(ssttype string) {
	for key, sst := range logCtx.SSTs {
		if len(logCtx.SSTs) == 1 || (logCtx.State() == "DONOR" && utils.SliceContains(logCtx.OwnNames, key)) || (logCtx.State() == "JOINER" && utils.SliceContains(logCtx.OwnNames, sst.Joiner)) {
			sst.Type = ssttype
			logCtx.SSTs[key] = sst
			return
		}
	}
}

func (logCtx *LogCtx) ConfirmSSTMetadata(shiftTimestamp time.Time) {
	if logCtx.State() != "DONOR" && logCtx.State() != "JOINER" {
		return
	}
	for key, sst := range logCtx.SSTs {
		if sst.MustHaveHappenedLocally(shiftTimestamp) {
			if logCtx.State() == "DONOR" {
				logCtx.AddOwnName(key, shiftTimestamp)
			}
			if logCtx.State() == "JOINER" {
				logCtx.AddOwnName(sst.Joiner, shiftTimestamp)
			}
		}
	}

	return
}

func (logCtx *LogCtx) MarshalJSON() ([]byte, error) {
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
		FilePath:               logCtx.FilePath,
		FileType:               logCtx.FileType,
		OwnIPs:                 logCtx.OwnIPs,
		OwnHashes:              logCtx.OwnHashes,
		StateErrorLog:          logCtx.stateErrorLog,
		StateRecoveryLog:       logCtx.stateRecoveryLog,
		StatePostProcessingLog: logCtx.statePostProcessingLog,
		StateBackupLog:         logCtx.stateBackupLog,
		Version:                logCtx.Version,
		SSTs:                   logCtx.SSTs,
		MyIdx:                  logCtx.MyIdx,
		MemberCount:            logCtx.MemberCount,
		Desynced:               logCtx.Desynced,
		MinVerbosity:           logCtx.minVerbosity,
		Conflicts:              logCtx.Conflicts,
	})
}
