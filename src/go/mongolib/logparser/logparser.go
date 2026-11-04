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

// Package logparser reads the slow queries written by mongod/mongos to the diagnostic log
// and converts them to proto.SystemProfile documents, so they can be processed the same
// way as documents read from the system.profile collection.
//
// Both the structured JSON log format (MongoDB 4.4+) and the plain text format used by
// MongoDB 4.2 and earlier are supported. The format is detected line by line.
package logparser

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"net"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

// MaxLineSize is the maximum size of a single log line
var MaxLineSize = 64 * 1024 * 1024

// Options are used to filter the log entries
type Options struct {
	// If not zero, entries before Since or after Until are skipped
	Since time.Time
	Until time.Time
	// OnError, if set, is called for every slow query entry that cannot be parsed
	OnError func(lineNumber int, err error)
}

// Counters has information about the parsed lines
type Counters struct {
	Lines       int // total number of lines read
	SlowQueries int // lines identified as slow query entries
	Parsed      int // slow query entries returned to the caller
	Unparsable  int // slow query entries that could not be parsed and were skipped
	OutOfRange  int // slow query entries skipped because of the Since/Until options
	Ignored     int // slow query entries with no query shape (internal operations, write batches whose statements were logged)
}

type connInfo struct {
	remote string
	user   string
}

// Parser parses MongoDB log files. The same parser should be used for all the log files
// of a server (in chronological order) so connection information (client address and
// authenticated user) can be tracked across rotated files.
type Parser struct {
	opts     Options
	conns    map[string]*connInfo
	counters Counters
	// connections with a slow update/remove statement logged after their last entry
	statements map[string]bool
	lineNum    int // line number in the current reader
}

// New returns a new log parser
func New(opts Options) *Parser {
	return &Parser{
		opts:       opts,
		conns:      make(map[string]*connInfo),
		statements: make(map[string]bool),
	}
}

// Counters returns information about the lines processed so far
func (p *Parser) Counters() Counters {
	return p.counters
}

// Parse reads the log from r and calls fn for every slow query found. Parsing stops if fn
// returns an error.
func (p *Parser) Parse(r io.Reader, fn func(proto.SystemProfile) error) error {
	p.lineNum = 0
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 1024*1024), MaxLineSize)

	for scanner.Scan() {
		doc, ok := p.ParseLine(scanner.Bytes())
		if !ok {
			continue
		}
		if err := fn(doc); err != nil {
			return err
		}
	}
	return scanner.Err()
}

// ParseLine parses a single log line. It returns true if the line is a slow query entry
// that must be processed. Lines with connection information are used to keep track
// of the client address and authenticated user of each connection.
func (p *Parser) ParseLine(line []byte) (proto.SystemProfile, bool) {
	p.counters.Lines++
	p.lineNum++

	line = bytes.TrimSpace(line)
	if len(line) == 0 {
		return proto.SystemProfile{}, false
	}

	var (
		entry *slowQuery
		err   error
	)
	if line[0] == '{' {
		entry, err = p.parseJSONLine(line)
	} else {
		entry, err = p.parseLegacyLine(string(line))
	}

	if entry == nil {
		return proto.SystemProfile{}, false
	}
	p.counters.SlowQueries++

	if err != nil {
		p.counters.Unparsable++
		if p.opts.OnError != nil {
			p.opts.OnError(p.lineNum, err)
		}
		return proto.SystemProfile{}, false
	}
	if entry.ignore || p.isLoggedWriteBatch(entry) {
		p.counters.Ignored++
		return proto.SystemProfile{}, false
	}
	if (!p.opts.Since.IsZero() && entry.doc.Ts.Before(p.opts.Since)) ||
		(!p.opts.Until.IsZero() && entry.doc.Ts.After(p.opts.Until)) {
		p.counters.OutOfRange++
		return proto.SystemProfile{}, false
	}

	if conn, ok := p.conns[entry.ctx]; ok {
		if entry.doc.Client == "" {
			entry.doc.Client = conn.remote
		}
		if entry.doc.User == "" {
			entry.doc.User = conn.user
		}
	}
	entry.doc.Client = stripPort(entry.doc.Client)

	p.counters.Parsed++
	return entry.doc, true
}

// slowQuery is a slow query log entry
type slowQuery struct {
	ctx    string // connection, e.g. conn12
	doc    proto.SystemProfile
	ignore bool
}

func (p *Parser) connAccepted(ctx, remote string) {
	p.conns[ctx] = &connInfo{remote: remote}
}

func (p *Parser) connEnded(ctx string) {
	delete(p.conns, ctx)
	delete(p.statements, ctx)
}

// isLoggedWriteBatch returns true for the command level entry of an update or delete
// command whose statements were logged on their own entries (with type "update" or
// "remove"). The command level entry has no query shape (the statements are sent as a
// separate document sequence) so it is ignored to avoid counting its time twice.
//
// A batch can be slow even if none of its statements is (e.g. waiting for the write
// concern). In that case there is no statement entry and the batch entry is reported.
// A connection runs one operation at a time, so the statement entries of a batch are
// always logged right before the batch entry, on the same connection.
func (p *Parser) isLoggedWriteBatch(entry *slowQuery) bool {
	switch {
	case entry.doc.Op == "update" || entry.doc.Op == "remove":
		p.statements[entry.ctx] = true
		return false
	case isWriteBatch(entry.doc.Op, entry.doc.Command):
		logged := p.statements[entry.ctx]
		delete(p.statements, entry.ctx)
		return logged
	default:
		delete(p.statements, entry.ctx)
		return false
	}
}

func (p *Parser) connRemote(ctx, remote string) {
	if remote == "" {
		return
	}
	if conn, ok := p.conns[ctx]; ok {
		conn.remote = remote
		return
	}
	p.conns[ctx] = &connInfo{remote: remote}
}

func (p *Parser) connAuthenticated(ctx, user, db string) {
	if user == "" {
		return
	}
	if db != "" {
		user += "@" + db
	}
	if conn, ok := p.conns[ctx]; ok {
		conn.user = user
		return
	}
	p.conns[ctx] = &connInfo{user: user}
}

// normalizeOp returns the operation name used by the profiler (system.profile "op" field),
// so queries read from the logs are grouped and fingerprinted like profiler documents.
func normalizeOp(logType string, command bson.D) string {
	op := strings.ToLower(logType)
	if op != "command" || len(command) == 0 {
		return op
	}
	switch command[0].Key {
	case "find":
		return "query"
	case "getMore":
		return "getmore"
	case "insert":
		return "insert"
	case "killCursors":
		return "killcursors"
	}
	return op
}

// isWriteBatch returns true for the command level entry of update and delete commands
func isWriteBatch(op string, command bson.D) bool {
	if op != "command" || len(command) == 0 {
		return false
	}
	switch command[0].Key {
	case "update", "delete":
		return true
	}
	return false
}

func stripPort(addr string) string {
	if host, _, err := net.SplitHostPort(addr); err == nil {
		return host
	}
	return addr
}

func connCtx(id int64) string {
	return fmt.Sprintf("conn%d", id)
}
