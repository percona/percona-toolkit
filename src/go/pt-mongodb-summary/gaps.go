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
	"context"
	"strings"
	"sync"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/x/mongo/driver"
	"go.mongodb.org/mongo-driver/x/mongo/driver/auth"
)

const (
	codeUnauthorized            = 13
	codeAuthenticationFailed    = 18
	codeNotPrimaryNoSecondaryOk = 13435
	codeNotPrimaryOrSecondary   = 13436

	remoteArbiterReason = "arbiter accepts no logins; run the tool on the arbiter host against localhost"
	memberStateReason   = "unavailable in this member state"
)

var beyondClusterMonitor = []string{"admin.system.users", "admin.system.roles", "getClusterParameter", "config system collections"}

type collectError struct {
	Section string
	Item    string
	Code    int32
	Reason  string
}

type gaps struct {
	mu          sync.Mutex
	isArbiter   bool
	memberState string
	list        []collectError
}

func (g *gaps) add(section, item, needs string, err error) {
	if err == nil {
		return
	}

	g.mu.Lock()
	defer g.mu.Unlock()

	reason, code, expected := classifyError(err, g.isArbiter, needs)
	if reason == memberStateReason && g.memberState != "" {
		reason = "unavailable in member state " + g.memberState
	}

	logGap(item, err.Error(), expected)
	g.list = append(g.list, collectError{Section: section, Item: item, Code: code, Reason: reason})
}

func (g *gaps) note(section, item, reason string, expected bool) {
	g.mu.Lock()
	defer g.mu.Unlock()

	logGap(item, reason, expected)
	g.list = append(g.list, collectError{Section: section, Item: item, Reason: reason})
}

func (g *gaps) setMemberState(state string) {
	g.mu.Lock()
	defer g.mu.Unlock()

	g.memberState = state
}

func logGap(item, detail string, expected bool) {
	if expected {
		log.Infof("cannot get %s: %s", item, detail)

		return
	}

	log.Warnf("[Warning] cannot get %s: %s\n", item, detail)
}

func classifyError(err error, isArbiter bool, needs string) (string, int32, bool) {
	if err == nil {
		return "", 0, true
	}

	code := errorCode(err)
	msg := err.Error()

	switch {
	case errors.Is(err, context.DeadlineExceeded) || mongo.IsTimeout(err):
		return "timed out", code, false
	case isArbiter && strings.Contains(msg, "requires authentication"):
		return remoteArbiterReason, code, true
	case isArbiter && code == codeUnauthorized:
		return "arbiter accepts no logins", code, true
	case strings.Contains(msg, "connecting to a sharded cluster improperly"):
		return "connect through mongos", code, true
	case code == codeNotPrimaryOrSecondary || code == codeNotPrimaryNoSecondaryOk:
		return memberStateReason, code, true
	case code == codeAuthenticationFailed || isAuthError(err):
		return "authentication failed", code, false
	case code == codeUnauthorized:
		if needs == "" {
			return "not authorized", code, false
		}

		return "not authorized (needs " + needs + ")", code, lacksPrivilege(needs)
	}

	return msg, code, false
}

func lacksPrivilege(needs string) bool {
	for _, p := range beyondClusterMonitor {
		if strings.Contains(needs, p) {
			return true
		}
	}

	return false
}

func errorCode(err error) int32 {
	var ce mongo.CommandError
	if errors.As(err, &ce) {
		return ce.Code
	}

	var de driver.Error
	if errors.As(err, &de) {
		return de.Code
	}

	return 0
}

func isAuthError(err error) bool {
	var ae *auth.Error

	return errors.As(err, &ae)
}
