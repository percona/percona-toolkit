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
	"regexp"
	"strconv"
	"time"

	"go.mongodb.org/mongo-driver/bson"
)

// Log message ids. See https://www.mongodb.com/docs/manual/reference/log-messages/
const (
	idSlowQuery          = 51803
	idConnectionAccepted = 22943
	idConnectionEnded    = 22944
	idClientMetadata     = 51800
	idAuthSucceeded      = 20250
	idAuthSucceededNew   = 5286306
)

// The id field is near the start of the line, so it can be extracted without decoding
// the whole line. Lines with ids we don't care about are discarded quickly.
var reJSONID = regexp.MustCompile(`"id":\s*(\d+)`)

type jsonLine struct {
	T    time.Time `bson:"t"`
	ID   int64     `bson:"id"`
	Ctx  string    `bson:"ctx"`
	Msg  string    `bson:"msg"`
	Attr bson.Raw  `bson:"attr"`
}

type jsonSlowQueryAttr struct {
	Type               string        `bson:"type"`
	Ns                 string        `bson:"ns"`
	AppName            string        `bson:"appName"`
	Command            bson.RawValue `bson:"command"` // a string for unrecognized commands
	OriginatingCommand bson.D        `bson:"originatingCommand"`
	PlanSummary        string        `bson:"planSummary"`
	KeysExamined       int64         `bson:"keysExamined"`
	DocsExamined       int64         `bson:"docsExamined"`
	NReturned          int64         `bson:"nreturned"`
	NumYields          int64         `bson:"numYields"`
	Reslen             int64         `bson:"reslen"`
	WriteConflicts     int64         `bson:"writeConflicts"`
	QueryHash          string        `bson:"queryHash"`
	PlanCacheShapeHash string        `bson:"planCacheShapeHash"` // queryHash was renamed in 8.0
	Locks              bson.Raw      `bson:"locks"`
	Storage            bson.Raw      `bson:"storage"`
	Remote             string        `bson:"remote"`
	Protocol           string        `bson:"protocol"`
	DurationMillis     int64         `bson:"durationMillis"`
}

type jsonConnAttr struct {
	Remote       string `bson:"remote"`
	ConnectionID int64  `bson:"connectionId"`

	// Authentication. Field names changed between versions.
	PrincipalName          string `bson:"principalName"`
	User                   string `bson:"user"`
	AuthenticationDatabase string `bson:"authenticationDatabase"`
	DB                     string `bson:"db"`
}

// parseJSONLine parses a line of the structured log format (MongoDB 4.4+). It returns a nil
// entry for lines that are not slow queries.
func (p *Parser) parseJSONLine(line []byte) (*slowQuery, error) {
	head := line
	if len(head) > 256 {
		head = head[:256]
	}
	m := reJSONID.FindSubmatch(head)
	if m == nil {
		return nil, nil
	}
	id, _ := strconv.ParseInt(string(m[1]), 10, 64)

	switch id {
	case idSlowQuery, idConnectionAccepted, idConnectionEnded, idClientMetadata, idAuthSucceeded, idAuthSucceededNew:
	default:
		return nil, nil
	}

	var jl jsonLine
	if err := bson.UnmarshalExtJSON(line, false, &jl); err != nil {
		if id == idSlowQuery {
			return &slowQuery{}, err
		}
		return nil, nil
	}

	if id != idSlowQuery {
		p.jsonConnectionEvent(&jl)
		return nil, nil
	}

	var attr jsonSlowQueryAttr
	if err := bson.Unmarshal(jl.Attr, &attr); err != nil {
		return &slowQuery{}, err
	}

	entry := &slowQuery{ctx: jl.Ctx}
	var command bson.D
	if attr.Command.Type == bson.TypeEmbeddedDocument {
		if err := attr.Command.Unmarshal(&command); err != nil {
			return entry, err
		}
	}
	op := normalizeOp(attr.Type, command)
	// "none" is used by internal operations (e.g. index builds, that are also logged as
	// a createIndexes command) and commands that failed before being parsed.
	if op == "none" || len(command) == 0 {
		entry.ignore = true
		return entry, nil
	}

	doc := &entry.doc
	doc.Ts = jl.T
	doc.Op = op
	doc.Ns = attr.Ns
	doc.AppName = attr.AppName
	doc.Command = command
	doc.OriginatingCommand = attr.OriginatingCommand
	doc.PlanSummary = attr.PlanSummary
	doc.KeysExamined = int(attr.KeysExamined)
	doc.DocsExamined = int(attr.DocsExamined)
	doc.Nreturned = int(attr.NReturned)
	doc.NumYield = int(attr.NumYields)
	doc.ResponseLength = int(attr.Reslen)
	doc.WriteConflicts = int(attr.WriteConflicts)
	doc.QueryHash = attr.QueryHash
	if doc.QueryHash == "" {
		doc.QueryHash = attr.PlanCacheShapeHash
	}
	doc.Client = attr.Remote
	doc.Protocol = attr.Protocol
	doc.Millis = int(attr.DurationMillis)

	if len(attr.Locks) > 0 {
		if err := bson.Unmarshal(attr.Locks, &doc.Locks); err != nil {
			return entry, err
		}
	}
	if len(attr.Storage) > 0 {
		if err := bson.Unmarshal(attr.Storage, &doc.Storage); err != nil {
			return entry, err
		}
	}

	if comment, ok := command.Map()["comment"].(string); ok {
		doc.Comments = comment
	}

	return entry, nil
}

func (p *Parser) jsonConnectionEvent(jl *jsonLine) {
	var attr jsonConnAttr
	if len(jl.Attr) > 0 {
		if err := bson.Unmarshal(jl.Attr, &attr); err != nil {
			return
		}
	}

	switch jl.ID {
	case idConnectionAccepted:
		p.connAccepted(connCtx(attr.ConnectionID), attr.Remote)
	case idConnectionEnded:
		p.connEnded(jl.Ctx)
	case idClientMetadata:
		p.connRemote(jl.Ctx, attr.Remote)
	case idAuthSucceeded, idAuthSucceededNew:
		user := attr.PrincipalName
		if user == "" {
			user = attr.User
		}
		db := attr.AuthenticationDatabase
		if db == "" {
			db = attr.DB
		}
		p.connAuthenticated(jl.Ctx, user, db)
	}
}
