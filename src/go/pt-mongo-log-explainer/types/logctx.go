// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
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

package types

import (
	"encoding/json"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
)

// LogCtx is the main context storage for a node.
// It is the principal storage of this tool, this is the source of truth to merge logs and take decisions
// It is stored along with each single log line we matched, and copied for each new log line.
// It is NOT meant to be used as a singleton by pointer, it must keep its original state for each log lines
// If not, every information would be overwritten (states, version, membercount, ...) and we would not be able to give the history of changes
type LogCtx struct {
	FilePath         string
	FileType         string
	OwnIPs           []string
	OwnHashes        []string
	OwnNames         []string
	state            string
	Version          string
	OperatorMetadata *OperatorMetadata

	MyIdx        string
	MemberCount  int
	minVerbosity Verbosity
}

func NewLogCtx() LogCtx {
	return LogCtx{minVerbosity: Debug}
}

// State returns the last known replica-set member state parsed from mongod logs.
func (logCtx LogCtx) State() string {
	return logCtx.state
}

func (logCtx *LogCtx) SetState(s string) {
	valid := []string{
		"PRIMARY", "SECONDARY", "ARBITER", "STARTUP", "STARTUP2",
		"RECOVERING", "ROLLBACK", "REMOVED", "DOWN",
	}
	if !utils.SliceContains(valid, s) {
		return
	}
	logCtx.state = s
}

func (logCtx *LogCtx) HasVisibleEvents(level Verbosity) bool {
	return level >= logCtx.minVerbosity
}

func (logCtx *LogCtx) IsPrimary() bool {
	return logCtx.State() == "PRIMARY"
}

// AddOwnName propagates a name into the translation maps using the trusted node's known own hashes and ips
func (logCtx *LogCtx) AddOwnName(name string, date time.Time) {
	name = utils.ShortNodeName(name)
	if len(logCtx.OwnNames) > 0 && logCtx.OwnNames[len(logCtx.OwnNames)-1] == name {
		return
	}
	logCtx.OwnNames = append(logCtx.OwnNames, name)

	if lenIPs := len(logCtx.OwnIPs); lenIPs > 0 {
		translate.AddIPToNodeName(logCtx.OwnIPs[lenIPs-1], name, date)
	}
}

// AddOwnHash propagates a hash into the translation maps
func (logCtx *LogCtx) AddOwnHash(hash string, date time.Time) {
	if utils.SliceContains(logCtx.OwnHashes, hash) {
		return
	}
	logCtx.OwnHashes = append(logCtx.OwnHashes, hash)

	if lenIPs := len(logCtx.OwnIPs); lenIPs > 0 {
		translate.AddHashToIP(hash, logCtx.OwnIPs[lenIPs-1], date)
	}
	if lenNodeNames := len(logCtx.OwnNames); lenNodeNames > 0 {
		translate.AddHashToNodeName(hash, logCtx.OwnNames[lenNodeNames-1], date)
	}
}

// AddOwnIP propagates an ip into the translation maps
func (logCtx *LogCtx) AddOwnIP(ip string, date time.Time) {
	if len(logCtx.OwnIPs) > 0 && logCtx.OwnIPs[len(logCtx.OwnIPs)-1] == ip {
		return
	}
	logCtx.OwnIPs = append(logCtx.OwnIPs, ip)

	if lenNodeNames := len(logCtx.OwnNames); lenNodeNames > 0 {
		translate.AddIPToNodeName(ip, logCtx.OwnNames[lenNodeNames-1], date)
	}
}

// Inherit will fill the local information from given context into the base.
// It is used when merging, so that we do not start from nothing.
func (base *LogCtx) Inherit(logCtx LogCtx) {
	base.OwnHashes = append(logCtx.OwnHashes, base.OwnHashes...)
	base.OwnNames = append(logCtx.OwnNames, base.OwnNames...)
	base.OwnIPs = append(logCtx.OwnIPs, base.OwnIPs...)
	if base.Version == "" {
		base.Version = logCtx.Version
	}
}

func (logCtx *LogCtx) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		FilePath     string
		FileType     string
		OwnIPs       []string
		OwnHashes    []string
		OwnNames     []string
		State        string
		Version      string
		MyIdx        string
		MemberCount  int
		MinVerbosity Verbosity
	}{
		FilePath:     logCtx.FilePath,
		FileType:     logCtx.FileType,
		OwnIPs:       logCtx.OwnIPs,
		OwnHashes:    logCtx.OwnHashes,
		State:        logCtx.state,
		Version:      logCtx.Version,
		MyIdx:        logCtx.MyIdx,
		MemberCount:  logCtx.MemberCount,
		MinVerbosity: logCtx.minVerbosity,
	})
}
