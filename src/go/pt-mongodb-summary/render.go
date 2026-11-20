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
	"bytes"
	"fmt"
	"math"
	"strings"
	"sync"
	"text/template"
	"time"
	"unicode/utf8"

	log "github.com/sirupsen/logrus"

	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/templates"
)

const headerWidth = 106

var (
	reportFuncs = template.FuncMap{
		"bytes":  formatBytes,
		"rate":   formatRate,
		"pct":    formatPct,
		"utc":    formatTime,
		"dur":    formatDuration,
		"header": header,
	}

	byteUnits = []string{"bytes", "KB", "MB", "GB", "TB", "PB", "EB"}

	parsedTemplates sync.Map
)

type reportSection struct {
	name string
	tmpl string
	data any
	show bool
}

func textSections(ci *collectedInfo) []reportSection {
	hi := ci.HostInfo
	isArbiter := hi != nil && hi.IsArbiter

	return []reportSection{
		{name: "Mongos", tmpl: templates.MongosInfo, data: ci.MongosInfo, show: ci.MongosInfo != nil},
		{name: "Shards", tmpl: templates.Shards, data: ci.ShardsInfo, show: ci.ShardsInfo != nil},
		{
			name: "Instances", tmpl: templates.Replicas, data: ci.ReplicaMembers,
			show: ci.ReplicaMembers != nil || (!isArbiter && !ci.hasGap("Instances")),
		},
		{name: "This host", tmpl: templates.HostInfo, data: hi, show: hi != nil},
		{name: "OS & Production Checks", tmpl: templates.OSChecks, data: ci.OSChecks, show: ci.OSChecks != nil},
		{
			name: "Command line arguments", tmpl: templates.CmdlineArgs, data: hi,
			show: hi != nil && len(hi.CmdlineArgs) > 0,
		},
		{name: "Startup Options", tmpl: templates.StartupOptions, data: ci.StartupOptions, show: ci.StartupOptions != nil},
		{name: "Running Ops", tmpl: templates.RunningOps, data: ci.RunningOps, show: ci.RunningOps != nil},
		{name: "WiredTiger", tmpl: templates.WiredTiger, data: ci.WiredTiger, show: ci.WiredTiger != nil},
		{name: "Memory", tmpl: templates.Memory, data: ci.Memory, show: ci.Memory != nil},
		{
			name: "Connections & Profiling", tmpl: templates.Connections, data: ci,
			show: ci.Connections != nil || ci.Profiling != nil,
		},
		{name: "Security", tmpl: templates.Security, data: ci.SecuritySettings, show: ci.SecuritySettings != nil},
		{name: "Oplog", tmpl: templates.Oplog, data: oplogView(ci.OplogInfo), show: len(ci.OplogInfo) > 0},
		{name: "Change Streams", tmpl: templates.ChangeStreams, data: ci.ChangeStreams, show: ci.ChangeStreams != nil},
		{
			name: "Database Inventory", tmpl: templates.DBInventory, data: ci.DatabaseInventory,
			show: ci.DatabaseInventory != nil,
		},
		{name: "Cluster wide", tmpl: templates.Clusterwide, data: ci.ClusterWideInfo, show: ci.ClusterWideInfo != nil},
		{name: "Balancer (per day)", tmpl: templates.BalancerStats, data: ci.BalancerStats, show: ci.BalancerStats != nil},
	}
}

func renderText(ci *collectedInfo) []byte {
	return renderSections(ci, textSections(ci))
}

func renderSections(ci *collectedInfo, sections []reportSection) []byte {
	var out bytes.Buffer

	for _, s := range sections {
		if !s.show {
			continue
		}

		var buf bytes.Buffer
		if err := executeTemplate(&buf, s.name, s.tmpl, s.data); err != nil {
			log.Warnf("[Warning] cannot render the %s section: %v\n", s.name, err)
			ci.Errors = append(ci.Errors, collectError{Section: s.name, Item: s.name, Reason: "cannot render: " + err.Error()})

			continue
		}

		out.Write(buf.Bytes())
	}

	if len(ci.Errors) == 0 {
		return out.Bytes()
	}

	var buf bytes.Buffer
	if err := executeTemplate(&buf, "Not collected", templates.NotCollected, ci.Errors); err != nil {
		log.Warnf("[Warning] cannot render the Not collected section: %v\n", err)

		return out.Bytes()
	}

	if out.Len() > 0 && !bytes.HasSuffix(out.Bytes(), []byte("\n")) {
		out.WriteByte('\n')
	}
	out.Write(buf.Bytes())

	return out.Bytes()
}

func executeTemplate(buf *bytes.Buffer, name, src string, data any) error {
	key := name + "\x00" + src

	if t, ok := parsedTemplates.Load(key); ok {
		return t.(*template.Template).Execute(buf, data)
	}

	t, err := template.New(name).Funcs(reportFuncs).Parse(src)
	if err != nil {
		return err
	}

	parsedTemplates.Store(key, t)

	return t.Execute(buf, data)
}

func (ci *collectedInfo) hasGap(section string) bool {
	for _, e := range ci.Errors {
		if e.Section == section {
			return true
		}
	}

	return false
}

func formatBytes(n int64) string {
	v := float64(n)
	i := 0

	for i < len(byteUnits)-1 && math.Abs(v) >= 1024 {
		v /= 1024
		i++
	}

	if i < len(byteUnits)-1 && math.Abs(v) >= 1023.995 {
		v /= 1024
		i++
	}

	return fmt.Sprintf("%.2f %s", v, byteUnits[i])
}

func formatRate(v float64) string {
	switch a := math.Abs(v); {
	case math.IsNaN(v) || math.IsInf(v, 0):
		return "-"
	case v == 0:
		return "0"
	case a < 10:
		return fmt.Sprintf("%.2f", v)
	case a < 1000:
		return fmt.Sprintf("%.1f", v)
	default:
		return fmt.Sprintf("%.0f", v)
	}
}

func formatPct(v float64) string {
	return fmt.Sprintf("%.1f%%", v)
}

func formatTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}

	return t.UTC().Format("2006-01-02 15:04:05 UTC")
}

func formatDuration(d time.Duration) string {
	if d < time.Hour {
		return fmt.Sprintf("%.1fs", d.Seconds())
	}

	m := int64(d.Round(time.Minute) / time.Minute)
	if m >= 24*60 {
		return fmt.Sprintf("%dd %02dh %02dm", m/(24*60), m/60%24, m%60)
	}

	return fmt.Sprintf("%dh %02dm", m/60, m%60)
}

func header(title string) string {
	h := "# " + title
	if pad := headerWidth - utf8.RuneCountInString(h) - 1; pad > 0 {
		h += " " + strings.Repeat("#", pad)
	}

	return h
}
