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

package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/oplog"
)

type memberDetail struct {
	Host      string
	Priority  *float64
	Votes     *float64
	Hidden    bool
	DelaySecs int64
}

func roleText(state string, hidden bool, delaySecs int64, setRole string) string {
	if state == "" {
		return ""
	}

	if setRole != "" {
		state = setRole + "/" + state
	}

	return withTags(state, hidden, delaySecs)
}

func withTags(state string, hidden bool, delaySecs int64) string {
	if state == "" {
		return ""
	}

	var tags []string
	if hidden {
		tags = append(tags, "hidden")
	}
	if delaySecs > 0 {
		tags = append(tags, fmt.Sprintf("delayed %d s", delaySecs))
	}

	if len(tags) == 0 {
		return state
	}

	return state + " (" + strings.Join(tags, ", ") + ")"
}

func withSetRole(members []oplog.Member, clusterRole string) []oplog.Member {
	role := strings.ToUpper(clusterRole)
	if role == "" {
		return members
	}

	for i := range members {
		if members[i].SetRole == "" && !members[i].ViaShardMap {
			members[i].SetRole = role
		}
	}

	return members
}

func withEntryFacts(walked []oplog.Member, snap *snapshot) []oplog.Member {
	out := append([]oplog.Member(nil), walked...)

	for i := range out {
		m := &out[i]
		if !m.Self {
			continue
		}

		if pid, ok := rawInt64(snap.ServerStatus, "pid"); ok && m.Pid == 0 {
			m.Pid = pid
		}
		if doc, ok := rawDoc(snap.ServerStatus, "storageEngine"); ok && m.Engine.Name == "" {
			if err := bson.Unmarshal(doc, &m.Engine); err != nil {
				m.Engine = proto.StorageEngine{}
			}
		}
		if hidden, _ := rawBool(snap.IsMasterRaw, "hidden"); hidden {
			m.Hidden = true
		}
		if m.DelaySecs == 0 {
			if delay, ok := rawInt64(snap.IsMasterRaw, "secondaryDelaySecs"); ok {
				m.DelaySecs = delay
			} else if delay, ok := rawInt64(snap.IsMasterRaw, "slaveDelay"); ok {
				m.DelaySecs = delay
			}
		}
	}

	return out
}

func setHostRole(hi *hostInfo, walked []oplog.Member) {
	for _, m := range walked {
		if !m.Self {
			continue
		}

		hi.ReplRole = roleText(m.State, m.Hidden, m.DelaySecs, m.SetRole)
		hi.Hidden, hi.DelaySecs = m.Hidden, m.DelaySecs
		hi.Priority, hi.Votes = m.Priority, m.Votes

		return
	}
}

func buildInstances(walked []oplog.Member) ([]proto.Members, []memberDetail, int, int) {
	if len(walked) == 0 {
		return nil, nil, 0, 0
	}

	sorted := append([]oplog.Member(nil), walked...)
	sort.SliceStable(sorted, func(i, j int) bool { return sorted[i].Host < sorted[j].Host })

	members := make([]proto.Members, 0, len(sorted))
	details := make([]memberDetail, 0, len(sorted))
	read, total := 0, 0

	for _, m := range sorted {
		var pm proto.Members
		if len(m.Status) > 0 {
			if err := bson.Unmarshal(m.Status, &pm); err != nil {
				log.Debugf("cannot decode the replSetGetStatus entry of %s: %s", m.Host, err)
				pm = proto.Members{}
			}
		}

		pm.Name, pm.StateStr, pm.Set, pm.ID = m.Host, roleText(m.State, false, 0, m.SetRole), m.Set, m.Pid
		pm.StorageEngine = m.Engine
		members = append(members, pm)
		details = append(details, memberDetail{
			Host: m.Host, Priority: m.Priority, Votes: m.Votes, Hidden: m.Hidden, DelaySecs: m.DelaySecs,
		})

		if m.Arbiter && !m.Self {
			continue
		}

		total++
		if m.Pid > 0 {
			read++
		}
	}

	return members, details, read, total
}

type instancesTable struct {
	members []proto.Members
	details map[string]memberDetail
}

func instancesView(members []proto.Members, details []memberDetail) instancesTable {
	byHost := make(map[string]memberDetail, len(details))
	for _, d := range details {
		byHost[d.Host] = d
	}

	return instancesTable{members: members, details: byHost}
}

func (t instancesTable) Lines() []string {
	rows := [][]string{{"PID", "Host", "Type", "ReplSet", "Engine", "Priority", "Votes"}}

	for _, m := range t.members {
		d := t.details[m.Name]

		pid := ""
		if m.ID > 0 {
			pid = strconv.FormatInt(m.ID, 10)
		}

		set := m.Set
		if set == "" {
			set = "-"
		}

		rows = append(rows, []string{
			pid, cutMiddle(m.Name, oplogHostCap), withTags(m.StateStr, d.Hidden, d.DelaySecs), set,
			m.StorageEngine.Name, formatNumber(d.Priority), formatNumber(d.Votes),
		})
	}

	widths := make([]int, len(rows[0]))
	for _, r := range rows {
		for i, v := range r {
			widths[i] = max(widths[i], utf8.RuneCountInString(v))
		}
	}

	lines := make([]string, 0, len(rows)+1)
	for _, r := range rows {
		line := fmt.Sprintf("  %*s  %-*s  %-*s  %-*s  %-*s  %*s  %*s", widths[0], r[0], widths[1], r[1], widths[2], r[2],
			widths[3], r[3], widths[4], r[4], widths[5], r[5], widths[6], r[6])
		lines = append(lines, strings.TrimRight(line, " "))
	}

	if len(t.members) == 0 {
		lines = append(lines, "  no replica sets found")
	}

	return lines
}

func formatNumber(v *float64) string {
	if v == nil {
		return ""
	}

	return strconv.FormatFloat(*v, 'f', -1, 64)
}
