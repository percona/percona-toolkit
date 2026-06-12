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

package proto

import (
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
)

// docsExamined is renamed from nscannedObjects in 3.2.0
// json tags are used for PMM purposes
// https://docs.mongodb.com/manual/reference/database-profiler/#system.profile.docsExamined
type SystemProfile struct {
	AllUsers        []interface{} `bson:"allUsers" json:"allUsers"`
	Client          string        `bson:"client" json:"client"`
	CursorExhausted bool          `bson:"cursorExhausted" json:"cursorExhausted"`
	ExecStats       struct {
		Advanced                    int `bson:"advanced" json:"advanced"`
		ExecutionTimeMillisEstimate int `bson:"executionTimeMillisEstimate" json:"executionTimeMillisEstimate"`
		InputStage                  struct {
			Advanced                    int    `bson:"advanced" json:"advanced"`
			Direction                   string `bson:"direction" json:"direction"`
			DocsExamined                int    `bson:"docsExamined" json:"docsExamined"`
			ExecutionTimeMillisEstimate int    `bson:"executionTimeMillisEstimate" json:"executionTimeMillisEstimate"`
			Filter                      struct {
				Date struct {
					Eq string `bson:"$eq" json:"$eq"`
				} `bson:"date" json:"date"`
			} `bson:"filter" json:"filter"`
			Invalidates  int    `bson:"invalidates" json:"invalidates"`
			IsEOF        int    `bson:"isEOF" json:"isEOF"`
			NReturned    int    `bson:"nReturned" json:"nReturned"`
			NeedTime     int    `bson:"needTime" json:"needTime"`
			NeedYield    int    `bson:"needYield" json:"needYield"`
			RestoreState int    `bson:"restoreState" json:"restoreState"`
			SaveState    int    `bson:"saveState" json:"saveState"`
			Stage        string `bson:"stage" json:"stage"`
			Works        int    `bson:"works" json:"works"`
		} `bson:"inputStage" json:"inputStage"`
		Invalidates  int    `bson:"invalidates" json:"invalidates"`
		IsEOF        int    `bson:"isEOF" json:"isEOF"`
		LimitAmount  int    `bson:"limitAmount" json:"limitAmount"`
		NReturned    int    `bson:"nReturned" json:"nReturned"`
		NeedTime     int    `bson:"needTime" json:"needTime"`
		NeedYield    int    `bson:"needYield" json:"needYield"`
		RestoreState int    `bson:"restoreState" json:"restoreState"`
		SaveState    int    `bson:"saveState" json:"saveState"`
		Stage        string `bson:"stage" json:"stage"`
		Works        int    `bson:"works" json:"works"`
		DocsExamined int    `bson:"docsExamined" json:"docsExamined"`
	} `bson:"execStats" json:"execStats"`
	KeyUpdates   int `bson:"keyUpdates" json:"keyUpdates"`
	KeysExamined int `bson:"keysExamined" json:"keysExamined"`
	Locks        struct {
		Collection struct {
			AcquireCount struct {
				Read       int `bson:"R" json:"R"`
				ReadShared int `bson:"r" json:"r"`
			} `bson:"acquireCount" json:"acquireCount"`
		} `bson:"Collection" json:"Collection"`
		Database struct {
			AcquireCount struct {
				ReadShared int `bson:"r" json:"r"`
			} `bson:"acquireCount" json:"acquireCount"`
			AcquireWaitCount struct {
				ReadShared int `bson:"r" json:"r"`
			} `bson:"acquireWaitCount" json:"acquireWaitCount"`
			TimeAcquiringMicros struct {
				ReadShared int64 `bson:"r" json:"r"`
			} `bson:"timeAcquiringMicros" json:"timeAcquiringMicros"`
		} `bson:"Database" json:"Database"`
		Global struct {
			AcquireCount struct {
				ReadShared  int `bson:"r" json:"r"`
				WriteShared int `bson:"w" json:"w"`
			} `bson:"acquireCount" json:"acquireCount"`
		} `bson:"Global" json:"Global"`
		MMAPV1Journal struct {
			AcquireCount struct {
				ReadShared int `bson:"r" json:"r"`
			} `bson:"acquireCount" json:"acquireCount"`
		} `bson:"MMAPV1Journal" json:"MMAPV1Journal"`
	} `bson:"locks" json:"locks"`
	Millis             int       `bson:"millis" json:"durationMillis"`
	Nreturned          int       `bson:"nreturned" json:"nreturned"`
	Ns                 string    `bson:"ns" json:"ns"`
	NumYield           int       `bson:"numYield" json:"numYield"`
	Op                 string    `bson:"op" json:"op"`
	PlanSummary        string    `bson:"planSummary" json:"planSummary"`
	Protocol           string    `bson:"protocol" json:"protocol"`
	Query              bson.D    `bson:"query" json:"query"`
	UpdateObj          bson.D    `bson:"updateobj" json:"updateobj"`
	Command            bson.D    `bson:"command" json:"command"`
	OriginatingCommand bson.D    `bson:"originatingCommand" json:"originatingCommand"`
	ResponseLength     int       `bson:"responseLength" json:"reslen"`
	Ts                 time.Time `bson:"ts" json:"ts"`
	User               string    `bson:"user" json:"user"`
	WriteConflicts     int       `bson:"writeConflicts" json:"writeConflicts"`
	DocsExamined       int       `bson:"docsExamined" json:"docsExamined"`
	QueryHash          string    `bson:"queryHash" json:"queryHash"`
	Storage            struct {
		Data struct {
			BytesRead         int64 `bson:"bytesRead" json:"bytesRead"`
			TimeReadingMicros int64 `bson:"timeReadingMicros" json:"timeReadingMicros"`
		} `bson:"data" json:"data"`
	} `bson:"storage" json:"storage"`
	AppName  string `bson:"appName" json:"appName"`
	Comments string `bson:"comments" json:"comments"`
}

func NewExampleQuery(doc SystemProfile) ExampleQuery {
	return ExampleQuery{
		Ns:                 doc.Ns,
		Op:                 doc.Op,
		Query:              doc.Query,
		Command:            doc.Command,
		OriginatingCommand: doc.OriginatingCommand,
		UpdateObj:          doc.UpdateObj,
	}
}

// ExampleQuery is a subset of SystemProfile
type ExampleQuery struct {
	Ns                 string `bson:"ns" json:"ns"`
	Op                 string `bson:"op" json:"op"`
	Query              bson.D `bson:"query,omitempty" json:"query,omitempty"`
	Command            bson.D `bson:"command,omitempty" json:"command,omitempty"`
	OriginatingCommand bson.D `bson:"originatingCommand,omitempty" json:"originatingCommand,omitempty"`
	UpdateObj          bson.D `bson:"updateobj,omitempty" json:"updateobj,omitempty"`
}

func (self ExampleQuery) Db() string {
	ns := strings.SplitN(self.Ns, ".", 2)
	if len(ns) > 0 {
		return ns[0]
	}
	return ""
}

// ExplainCmd returns bson.D ready to use in https://godoc.org/labix.org/v2/mgo#Database.Run
func (self ExampleQuery) ExplainCmd() bson.D {
	cmd := self.Command

	switch self.Op {
	case "query":
		if len(cmd) == 0 {
			cmd = self.Query
		}

		// MongoDB 2.6:
		//
		// "query" : {
		//   "query" : {
		//
		//   },
		//	 "$explain" : true
		// },
		if _, ok := cmd.Map()["$explain"]; ok {
			cmd = bson.D{
				{"explain", ""},
			}
			break
		}

		if len(cmd) == 0 || cmd[0].Key != "find" {
			var filter interface{}
			if len(cmd) > 0 && cmd[0].Key == "query" {
				filter = cmd[0].Value
			} else {
				filter = cmd
			}

			coll := ""
			s := strings.SplitN(self.Ns, ".", 2)
			if len(s) == 2 {
				coll = s[1]
			}

			cmd = bson.D{
				{"find", coll},
				{"filter", filter},
			}
		} else {
			for i := range cmd {
				switch cmd[i].Key {
				// PMM-1905: Drop "ntoreturn" if it's negative.
				case "ntoreturn":
					// If it's non-negative, then we are fine, continue to next param.
					if cmd[i].Value.(int64) >= 0 {
						continue
					}
					fallthrough
				// Drop $db as it is not supported in MongoDB 3.0.
				case "$db":
					if len(cmd)-1 == i {
						cmd = cmd[:i]
					} else {
						cmd = append(cmd[:i], cmd[i+1:]...)
					}
				}
			}
		}
	case "update":
		s := strings.SplitN(self.Ns, ".", 2)
		coll := ""
		if len(s) == 2 {
			coll = s[1]
		}
		if len(cmd) == 0 {
			cmd = bson.D{
				{Key: "q", Value: self.Query},
				{Key: "u", Value: self.UpdateObj},
			}
		}
		cmd = bson.D{
			{Key: "update", Value: coll},
			{Key: "updates", Value: []interface{}{cmd}},
		}
	case "remove":
		s := strings.SplitN(self.Ns, ".", 2)
		coll := ""
		if len(s) == 2 {
			coll = s[1]
		}
		if len(cmd) == 0 {
			cmd = bson.D{
				{Key: "q", Value: self.Query},
				// we can't determine if limit was 1 or 0 so we assume 0
				{Key: "limit", Value: 0},
			}
		}
		cmd = bson.D{
			{Key: "delete", Value: coll},
			{Key: "deletes", Value: []interface{}{cmd}},
		}
	case "insert":
		if len(cmd) == 0 {
			cmd = self.Query
		}
		if len(cmd) == 0 || cmd[0].Key != "insert" {
			coll := ""
			s := strings.SplitN(self.Ns, ".", 2)
			if len(s) == 2 {
				coll = s[1]
			}

			cmd = bson.D{
				{"insert", coll},
			}
		}
	case "getmore":
		if len(self.OriginatingCommand) > 0 {
			cmd = self.OriginatingCommand
			for i := range cmd {
				// drop $db param as it is not supported in MongoDB 3.0
				if cmd[i].Key == "$db" {
					if len(cmd)-1 == i {
						cmd = cmd[:i]
					} else {
						cmd = append(cmd[:i], cmd[i+1:]...)
					}
					break
				}
			}
		} else {
			cmd = bson.D{
				{Key: "getmore", Value: ""},
			}
		}
	case "command":
		cmd = sanitizeCommand(cmd)

		if len(cmd) == 0 || cmd[0].Key != "group" {
			break
		}

		if group, ok := cmd[0].Value.(bson.D); ok {
			for i := range group {
				// for MongoDB <= 3.2
				// "$reduce" : function () {}
				// It is then Unmarshaled as empty value, so in essence not working
				//
				// for MongoDB >= 3.4
				// "$reduce" : {
				//    "code" : "function () {}"
				// }
				// It is then properly Unmarshaled but then explain fails with "not code"
				//
				// The $reduce function shouldn't affect explain execution plan (e.g. what indexes are picked)
				// so we ignore it for now until we find better way to handle this issue
				if group[i].Key == "$reduce" {
					group[i].Value = "{}"
					cmd[0].Value = group
					break
				}
			}
		}
	}

	return bson.D{
		{
			Key:   "explain",
			Value: cmd,
		},
	}
}

func sanitizeCommand(cmd bson.D) bson.D {
	if len(cmd) < 1 {
		return cmd
	}

	key := cmd[0].Key
	if key != "count" && key != "distinct" {
		return cmd
	}

	for i := range cmd {
		// drop $db param as it is not supported in MongoDB 3.0
		if cmd[i].Key == "$db" {
			if len(cmd)-1 == i {
				cmd = cmd[:i]
			} else {
				cmd = append(cmd[:i], cmd[i+1:]...)
			}
			break
		}
	}

	return cmd
}
