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

package parser

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/translate"
)

// ScanContext holds identity inferred from a single log file.
// ServerHost/ServerPort describe this mongod/mongos instance (for timeline columns).
// ClientIP is the last remote peer from "connection accepted" and is not used for HostPort().
// SourcePath is the log file path (used as a stable node label when hostname is not parsed yet).
type ScanContext struct {
	SourcePath string
	ServerHost string
	ServerPort string
	ServerIP   string // from bindIp or net.bindIp option
	ClientIP   string
	RSName     string
	Version    string
	Process    string // mongod | mongos | ""
	MeHostPort string // from JSON attr "host": "h:port"
}

var (
	reHostEq      = regexp.MustCompile(`(?i)\bhost=([a-zA-Z0-9._-]+)`)
	rePortEq      = regexp.MustCompile(`(?i)\bport=([0-9]{2,6})\b`)
	reMongoStart  = regexp.MustCompile(`(?i)MongoDB starting.*host=([a-zA-Z0-9._-]+)`)
	reReplSet     = regexp.MustCompile(`(?i)replica\s+set\s+([a-zA-Z0-9_-]{2,64})|replSet[^a-zA-Z0-9_]+([a-zA-Z0-9_-]{2,64})`)
	reVersion     = regexp.MustCompile(`(?i)db version v([0-9]+\.[0-9]+\.[0-9]+)`)
	reMongos      = regexp.MustCompile(`(?i)\bmongos\b`)
	reConnFrom    = regexp.MustCompile(`(?i)connection accepted from ([0-9.]+):([0-9]+)`)
	rePIDPortHost = regexp.MustCompile(`(?i)pid=\d+\s+port=([0-9]{2,6})\s+64-bit\s+host=([a-zA-Z0-9._-]+)`)
	reReplSetName = regexp.MustCompile(`(?i)replSetName:\s*"([^"]+)"`)
	reRSConfigID  = regexp.MustCompile(`(?i)Replica Set Config:\s*\{\s*_id:\s*"([^"]+)"`)
	reBindIP      = regexp.MustCompile(`(?i)bindIp[^0-9]*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})`)
)

// HostPort returns this server's host:port for display (not client addresses).
func (s *ScanContext) HostPort() string {
	if s.MeHostPort != "" {
		return s.MeHostPort
	}
	if s.ServerHost != "" && s.ServerPort != "" {
		return s.ServerHost + ":" + s.ServerPort
	}
	if s.ServerHost != "" {
		return s.ServerHost
	}
	return ""
}

// NodeLabel prefers short server hostname, else log file basename (so merged timelines stay distinguishable).
func (s *ScanContext) NodeLabel() string {
	if s.ServerHost != "" {
		h := s.ServerHost
		if i := strings.IndexByte(h, '.'); i > 0 {
			return h[:i]
		}
		return h
	}
	if s.SourcePath != "" {
		base := filepath.Base(s.SourcePath)
		base = strings.TrimSuffix(base, ".log")
		return base
	}
	return "unknown"
}

// UpdateFromText extracts identity hints from a plain-text mongod line.
func (s *ScanContext) UpdateFromText(line string) {
	if reMongos.MatchString(line) {
		s.Process = "mongos"
	}
	if m := reMongoStart.FindStringSubmatch(line); len(m) > 1 {
		s.ServerHost = m[1]
		if s.Process == "" {
			s.Process = "mongod"
		}
	}
	if m := rePIDPortHost.FindStringSubmatch(line); len(m) > 2 {
		s.ServerPort = m[1]
		s.ServerHost = m[2]
		if s.Process == "" {
			s.Process = "mongod"
		}
	}
	if m := reHostEq.FindStringSubmatch(line); len(m) > 1 {
		// startup / control lines: host= is this node
		if strings.Contains(strings.ToLower(line), "mongodb starting") ||
			strings.Contains(strings.ToLower(line), "control") ||
			strings.Contains(strings.ToLower(line), "initandlisten") {
			s.ServerHost = m[1]
		}
	}
	if m := rePortEq.FindStringSubmatch(line); len(m) > 1 {
		if strings.Contains(strings.ToLower(line), "mongodb starting") ||
			strings.Contains(strings.ToLower(line), "control") ||
			strings.Contains(strings.ToLower(line), "initandlisten") ||
			strings.Contains(strings.ToLower(line), "waiting for connections") {
			s.ServerPort = m[1]
		}
	}
	if m := reReplSet.FindStringSubmatch(line); len(m) > 1 {
		rs := m[1]
		if rs == "" {
			rs = m[2]
		}
		rsLower := strings.ToLower(rs)
		if rs != "" && rsLower != "initiate" && rsLower != "config" &&
			rsLower != "member" && rsLower != "starting" && rsLower != "state" {
			s.RSName = rs
		}
	}
	if m := reReplSetName.FindStringSubmatch(line); len(m) > 1 {
		s.RSName = m[1]
	}
	low := strings.ToLower(line)
	if strings.Contains(low, "db version v") {
		if m := reVersion.FindStringSubmatch(line); len(m) > 1 {
			s.Version = m[1]
		}
	}
	if m := reConnFrom.FindStringSubmatch(line); len(m) > 1 {
		s.ClientIP = m[1]
	}
	if strings.Contains(strings.ToLower(line), "replica set config:") {
		if m := reRSConfigID.FindStringSubmatch(line); len(m) > 1 && s.RSName == "" {
			s.RSName = m[1]
		}
	}
	if m := reBindIP.FindStringSubmatch(line); len(m) > 1 {
		ip := m[1]
		if ip != "0.0.0.0" && ip != "127.0.0.1" {
			s.ServerIP = ip
		}
	}
}

// UpdateFromJSONAttr merges common JSON log attr fields into context.
func (s *ScanContext) UpdateFromJSONAttr(attr map[string]interface{}, msg, c string) {
	if attr == nil {
		return
	}
	lc := strings.ToLower(c)
	lm := strings.ToLower(msg)

	// Only trust attr["host"] for this node's identity from startup/control lines,
	// not from replication config lines that list all members.
	isStartupLine := lc == "control" || strings.Contains(lm, "mongod startup") ||
		strings.Contains(lm, "mongos startup") || strings.Contains(lm, "mongodb starting") ||
		strings.Contains(lm, "options")
	if h, ok := attr["host"].(string); ok && isStartupLine && h != "" {
		if strings.Contains(h, ":") {
			s.MeHostPort = h
			parts := strings.SplitN(h, ":", 2)
			s.ServerHost = parts[0]
			s.ServerPort = parts[1]
		} else {
			s.ServerHost = h
		}
	}
	if p, ok := attr["port"]; ok && isStartupLine {
		port := jsonPortString(p)
		if port != "" {
			s.ServerPort = port
			if s.ServerHost != "" {
				s.MeHostPort = s.ServerHost + ":" + port
			}
		}
	}
	if setName, ok := attr["setName"].(string); ok {
		s.RSName = setName
	}
	if v, ok := attr["version"].(string); ok {
		s.Version = v
	}
	// "Build Info" line: attr.buildInfo.version
	if bi, ok := attr["buildInfo"].(map[string]interface{}); ok {
		if v, ok := bi["version"].(string); ok && v != "" {
			s.Version = v
		}
	}
	// "Options set by command line" line: attr.options.replication.replSet, attr.options.net.*
	if opts, ok := attr["options"].(map[string]interface{}); ok {
		if repl, ok := opts["replication"].(map[string]interface{}); ok {
			if rs, ok := repl["replSet"].(string); ok && rs != "" {
				s.RSName = rs
			}
		}
		if netObj, ok := opts["net"].(map[string]interface{}); ok {
			if bindIP, ok := netObj["bindIp"].(string); ok && bindIP != "0.0.0.0" && bindIP != "127.0.0.1" {
				s.ServerIP = bindIP
			}
			if p, ok := netObj["port"]; ok {
				port := jsonPortString(p)
				if port != "" {
					s.ServerPort = port
					if s.ServerHost != "" {
						s.MeHostPort = s.ServerHost + ":" + port
					}
				}
			}
		}
	}
	if _, ok := attr["mongos"].(map[string]interface{}); ok {
		s.Process = "mongos"
	}
	if netObj, ok := attr["net"].(map[string]interface{}); ok {
		if bindIP, ok := netObj["bindIp"].(string); ok && bindIP != "0.0.0.0" && bindIP != "127.0.0.1" {
			s.ServerIP = bindIP
		}
	}
	// "New replica set config in use" line: attr.config._id
	if cfg, ok := attr["config"].(map[string]interface{}); ok {
		if rsID, ok := cfg["_id"].(string); ok && rsID != "" && s.RSName == "" {
			s.RSName = rsID
		}
	}
	if lc == "shard" || lc == "sharding" || strings.Contains(lm, "chunk") || strings.Contains(lm, "balancer") {
		if s.Process == "" {
			s.Process = "mongos"
		}
	}
	if lc == "control" && strings.Contains(lm, "mongos") {
		s.Process = "mongos"
	}
	if lc == "control" && strings.Contains(lm, "mongod") {
		s.Process = "mongod"
	}
}

// FlushToTranslateDB pushes identity accumulated during parsing into the translate
// maps so that whois can resolve hostnames, host:port, and replica set names.
func (s *ScanContext) FlushToTranslateDB(ts time.Time) {
	name := s.NodeLabel()
	hp := s.HostPort()
	if name != "" && name != "unknown" {
		if hp != "" {
			translate.AddHostPortToNodeName(hp, name, ts)
		}
		if s.RSName != "" {
			translate.AddNodeNameToRSName(name, s.RSName, ts)
		}
		if s.ServerIP != "" {
			translate.AddIPToNodeName(s.ServerIP, name, ts)
		}
	}
}

func jsonPortString(v interface{}) string {
	switch x := v.(type) {
	case float64:
		return fmt.Sprintf("%.0f", x)
	case int:
		return fmt.Sprintf("%d", x)
	case int64:
		return fmt.Sprintf("%d", x)
	case string:
		return x
	default:
		return ""
	}
}
