// This program is copyright 2026 Percona LLC and/or its affiliates.
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

package logparser

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
)

// Plain text log format used by MongoDB 4.2 and earlier:
//
//	<timestamp> <severity> <component> [<context>] <message>
//
// Slow query messages look like:
//
//	command shop.orders appName: "app" command: find { find: "orders", ... } planSummary: COLLSCAN keysExamined:0 ... 103ms
//	update shop.orders appName: "app" command: { q: { ... }, u: { ... } } planSummary: IXSCAN { a: 1 } ... 15ms
var (
	reLegacyLine      = regexp.MustCompile(`^(\S+)\s+\S+\s+\S+\s+\[([^\]]+)\]\s(.*)$`)
	reLegacySlowQuery = regexp.MustCompile(`^(command|query|update|remove|insert|getmore|killcursors)\s+(\S+)\s(.*?)\s*(\d+)ms$`)
	reLegacyAccepted  = regexp.MustCompile(`^connection accepted from (\S+) #(\d+)`)
	reLegacyEnded     = regexp.MustCompile(`^end connection `)
	reLegacyMetadata  = regexp.MustCompile(`^received client metadata from (\S+) `)
	reLegacyAuth      = regexp.MustCompile(`^Successfully authenticated as principal (\S+) on (\S+)`)
	reLegacyKey       = regexp.MustCompile(`^([A-Za-z_$][A-Za-z0-9_$.]*):`)
)

var legacyTimeLayouts = []string{
	"2006-01-02T15:04:05.999Z0700", // iso8601-local (default) and iso8601-utc
	time.RFC3339Nano,
}

// Keys whose value is a document
var legacyDocKeys = map[string]bool{
	"command":            true,
	"originatingCommand": true,
	"query":              true,
	"update":             true,
	"locks":              true,
	"storage":            true,
}

// parseLegacyLine parses a line of the plain text log format. It returns a nil entry for
// lines that are not slow queries.
func (p *Parser) parseLegacyLine(line string) (*slowQuery, error) {
	m := reLegacyLine.FindStringSubmatch(line)
	if m == nil {
		return nil, nil
	}
	tsStr, ctx, msg := m[1], m[2], m[3]

	sq := reLegacySlowQuery.FindStringSubmatch(msg)
	if sq == nil {
		p.legacyConnectionEvent(ctx, msg)
		return nil, nil
	}

	entry := &slowQuery{ctx: ctx}
	ts, err := parseLegacyTime(tsStr)
	if err != nil {
		return entry, err
	}

	attrs, err := parseLegacyAttrs(sq[3])
	if err != nil {
		return entry, err
	}

	doc := &entry.doc
	doc.Ts = ts
	doc.Ns = sq[2]
	doc.Millis, _ = strconv.Atoi(sq[4])

	if cmd, ok := attrs.docs["command"]; ok {
		doc.Command = cmd
	}
	if cmd, ok := attrs.docs["originatingCommand"]; ok {
		doc.OriginatingCommand = cmd
	}
	// Very old versions (3.0, 3.2) log query/update instead of command
	if q, ok := attrs.docs["query"]; ok {
		doc.Query = q
	}
	if u, ok := attrs.docs["update"]; ok {
		doc.UpdateObj = u
	}
	if len(doc.Command) == 0 && len(doc.Query) == 0 {
		entry.ignore = true
		return entry, nil
	}

	doc.Op = normalizeOp(sq[1], doc.Command)

	doc.AppName = attrs.values["appName"]
	doc.PlanSummary = attrs.values["planSummary"]
	doc.KeysExamined = attrs.int("keysExamined")
	doc.DocsExamined = attrs.int("docsExamined")
	if doc.DocsExamined == 0 {
		doc.DocsExamined = attrs.int("nscannedObjects") // MongoDB < 3.2
	}
	if doc.KeysExamined == 0 {
		doc.KeysExamined = attrs.int("nscanned")
	}
	doc.Nreturned = attrs.int("nreturned")
	doc.NumYield = attrs.int("numYields")
	doc.ResponseLength = attrs.int("reslen")
	doc.WriteConflicts = attrs.int("writeConflicts")
	doc.QueryHash = attrs.values["queryHash"]
	doc.Protocol = attrs.values["protocol"]

	if locks, ok := attrs.docs["locks"]; ok {
		if err := convertDoc(locks, &doc.Locks); err != nil {
			return entry, err
		}
	}
	if storage, ok := attrs.docs["storage"]; ok {
		if err := convertDoc(storage, &doc.Storage); err != nil {
			return entry, err
		}
	}
	if comment, ok := doc.Command.Map()["comment"].(string); ok {
		doc.Comments = comment
	}

	return entry, nil
}

func (p *Parser) legacyConnectionEvent(ctx, msg string) {
	if m := reLegacyAccepted.FindStringSubmatch(msg); m != nil {
		p.connAccepted("conn"+m[2], m[1])
		return
	}
	if reLegacyEnded.MatchString(msg) {
		p.connEnded(ctx)
		return
	}
	if m := reLegacyMetadata.FindStringSubmatch(msg); m != nil {
		p.connRemote(ctx, m[1])
		return
	}
	if m := reLegacyAuth.FindStringSubmatch(msg); m != nil {
		p.connAuthenticated(ctx, m[1], m[2])
	}
}

func parseLegacyTime(s string) (time.Time, error) {
	var err error
	for _, layout := range legacyTimeLayouts {
		var ts time.Time
		// UTC, like the timestamps of the JSON logs and the profiler documents
		if ts, err = time.Parse(layout, s); err == nil {
			return ts.UTC(), nil
		}
	}
	return time.Time{}, err
}

type legacyAttrs struct {
	values map[string]string
	docs   map[string]bson.D
}

func (a legacyAttrs) int(key string) int {
	i, _ := strconv.Atoi(a.values[key])
	return i
}

// parseLegacyAttrs parses the "key: value key:value ..." part of a slow query message
func parseLegacyAttrs(s string) (legacyAttrs, error) {
	attrs := legacyAttrs{
		values: map[string]string{},
		docs:   map[string]bson.D{},
	}
	pos := 0
	skipWS := func() {
		for pos < len(s) && s[pos] == ' ' {
			pos++
		}
	}
	// readDoc parses the document at the current position
	readDoc := func() (bson.D, error) {
		doc, n, err := parseShellDoc(s[pos:])
		pos += n
		return doc, err
	}
	// readWord reads until the next space
	readWord := func() string {
		start := pos
		for pos < len(s) && s[pos] != ' ' {
			pos++
		}
		return s[start:pos]
	}

	for {
		skipWS()
		if pos >= len(s) {
			return attrs, nil
		}
		km := reLegacyKey.FindStringSubmatch(s[pos:])
		if km == nil {
			// Not a key (e.g. free text in an error message). Skip it.
			if s[pos] == '{' {
				if _, err := readDoc(); err != nil {
					return attrs, err
				}
				continue
			}
			readWord()
			continue
		}
		key := km[1]
		pos += len(km[0])
		skipWS()

		switch {
		case key == "planSummary":
			attrs.values[key] = readPlanSummary(s, &pos)
		case legacyDocKeys[key]:
			// "command: find { ... }" or "command: { ... }"
			if pos < len(s) && s[pos] != '{' {
				readWord()
				skipWS()
			}
			if pos >= len(s) || s[pos] != '{' {
				continue
			}
			doc, err := readDoc()
			if err != nil {
				if key == "command" || key == "query" {
					return attrs, fmt.Errorf("cannot parse %s: %s", key, err)
				}
				continue
			}
			attrs.docs[key] = doc
		case pos < len(s) && s[pos] == '"':
			p := &shellParser{s: s, pos: pos}
			str, err := p.parseString()
			if err != nil {
				return attrs, err
			}
			pos = p.pos
			attrs.values[key] = str
		case pos < len(s) && s[pos] == '{':
			if _, err := readDoc(); err != nil {
				return attrs, err
			}
		default:
			attrs.values[key] = readWord()
		}
	}
}

// readPlanSummary reads values like "COLLSCAN" or "IXSCAN { a: 1 }, IXSCAN { b: 1 }"
func readPlanSummary(s string, pos *int) string {
	start := *pos
	end := *pos
	for *pos < len(s) {
		for *pos < len(s) && s[*pos] == ' ' {
			*pos++
		}
		if *pos >= len(s) || reLegacyKey.MatchString(s[*pos:]) {
			break
		}
		if s[*pos] == '{' {
			_, n, err := parseShellDoc(s[*pos:])
			*pos += n
			if err != nil {
				break
			}
		} else {
			for *pos < len(s) && s[*pos] != ' ' {
				*pos++
			}
		}
		end = *pos
	}
	return strings.TrimSpace(s[start:end])
}

// convertDoc converts a bson.D into a struct using the bson tags
func convertDoc(d bson.D, v interface{}) error {
	b, err := bson.Marshal(d)
	if err != nil {
		return err
	}
	return bson.Unmarshal(b, v)
}
