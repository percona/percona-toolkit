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
	"testing"
	"time"

	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

type fakeSecuritySource struct {
	mode       string
	modeErr    error
	users      int64
	roles      int64
	countsErr  error
	countCalls int
}

func (f *fakeSecuritySource) tlsMode(context.Context) (string, error) {
	return f.mode, f.modeErr
}

func (f *fakeSecuritySource) userRoleCounts(context.Context) (int64, int64, error) {
	f.countCalls++

	return f.users, f.roles, f.countsErr
}

func TestEffectiveTLSMode(t *testing.T) {
	tests := []struct {
		param, tls, ssl string
		want            string
	}{
		{"requireTLS", "allowTLS", "requireSSL", "requireTLS"},
		{"disabled", "requireTLS", "", "disabled"},
		{"", "preferTLS", "requireSSL", "preferTLS"},
		{"", "", "requireSSL", "requireSSL"},
		{"", "", "", "disabled"},
	}

	for _, tt := range tests {
		assert.Equal(t, tt.want, effectiveTLSMode(tt.param, tt.tls, tt.ssl), "%+v", tt)
	}
}

func TestAuthMode(t *testing.T) {
	tests := []struct {
		name     string
		security bson.D
		want     string
	}{
		{"authorization enabled", bson.D{{Key: "authorization", Value: "enabled"}}, "enabled"},
		{"authorization disabled", bson.D{{Key: "authorization", Value: "disabled"}}, "disabled"},
		{"keyFile only", bson.D{{Key: "keyFile", Value: "/etc/mongo/keyfile"}}, "enabled"},
		{"x509 members", bson.D{{Key: "clusterAuthMode", Value: "x509"}}, "enabled"},
		{"sendX509", bson.D{{Key: "clusterAuthMode", Value: "sendX509"}}, "enabled"},
		{"sendKeyFile", bson.D{{Key: "clusterAuthMode", Value: "sendKeyFile"}}, "enabled"},
		{"clusterAuthMode keyFile without a key file", bson.D{{Key: "clusterAuthMode", Value: "keyFile"}}, "disabled"},
		{"transitionToAuth", bson.D{
			{Key: "keyFile", Value: "/etc/mongo/keyfile"},
			{Key: "transitionToAuth", Value: true},
		}, "not enforced (transitionToAuth)"},
		{"transitionToAuth false", bson.D{
			{Key: "authorization", Value: "enabled"},
			{Key: "transitionToAuth", Value: false},
		}, "enabled"},
		{"nothing", bson.D{}, "disabled"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, authMode(mustRaw(t, bson.D{{Key: "security", Value: tt.security}})))
		})
	}

	assert.Equal(t, "disabled", authMode(nil))
}

func TestEffectivePort(t *testing.T) {
	withPort := mustRaw(t, bson.D{{Key: "net", Value: bson.D{{Key: "port", Value: int32(37018)}}}})
	noPort := mustRaw(t, bson.D{{Key: "net", Value: bson.D{{Key: "bindIp", Value: "127.0.0.1"}}}})

	tests := []struct {
		name       string
		parsed     bson.Raw
		host, role string
		want       int64
	}{
		{"parsed port", withPort, "db:37019", "shardsvr", 37018},
		{"host from serverStatus", noPort, "db:37019", "", 37019},
		{"ipv6 host", noPort, "[::1]:37020", "", 37020},
		{"shardsvr default", noPort, "", "shardsvr", 27018},
		{"configsvr default", nil, "db", "configsvr", 27019},
		{"default", nil, "", "", 27017},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, effectivePort(tt.parsed, tt.host, tt.role))
		})
	}
}

func TestEffectiveBindIP(t *testing.T) {
	assert.Equal(t, "127.0.0.1,10.0.2.15",
		effectiveBindIP(mustRaw(t, bson.D{{Key: "net", Value: bson.D{{Key: "bindIp", Value: "127.0.0.1,10.0.2.15"}}}})))
	assert.Equal(t, "*", effectiveBindIP(mustRaw(t, bson.D{{Key: "net", Value: bson.D{{Key: "bindIp", Value: "*"}}}})))
	assert.Equal(t, "localhost", effectiveBindIP(mustRaw(t, bson.D{{Key: "net", Value: bson.D{{Key: "port", Value: int32(1)}}}})))
	assert.Equal(t, "localhost", effectiveBindIP(nil))
}

func TestSecurityBindIPWarnings(t *testing.T) {
	bindIP := "127.0.0.1, 8.8.8.8,10.10.1.11,192.168.1.5,*,localhost,::1,::,172.20.0.3"

	assert.Equal(t, []string{
		"Warning: You might be insecure (bind ip 8.8.8.8 is public)",
		"WARNING: You might be insecure. IP binding 192.168.1.5 is not localhost",
		"Warning: You might be insecure (bind ip * is public)",
		"Warning: You might be insecure (bind ip :: is public)",
		"WARNING: You might be insecure. IP binding 172.20.0.3 is not localhost",
	}, bindIPWarnings(bindIP, true, "10.10.1.11"))

	assert.Equal(t, []string{
		"Error. You are insecure: bind ip 8.8.8.8 is public and auth is disabled",
		"Error. You are insecure: bind ip * is public and auth is disabled",
		"Error. You are insecure: bind ip :: is public and auth is disabled",
	}, bindIPWarnings("8.8.8.8,*,::,10.10.1.11", false, "10.10.1.11"))

	assert.Empty(t, bindIPWarnings("127.0.0.1,localhost,::1,10.10.1.11", true, "10.10.1.11"))
}

func TestSecurityTLSAndLocalWarnings(t *testing.T) {
	snap := parsedOptionsSnapshot(t, bson.D{
		{Key: "net", Value: bson.D{
			{Key: "bindIp", Value: "127.0.0.1,8.8.8.8"},
			{Key: "tls", Value: bson.D{
				{Key: "mode", Value: "requireTLS"},
				{Key: "certificateKeyFile", Value: "/etc/ssl/mongo.pem"},
			}},
		}},
		{Key: "security", Value: bson.D{{Key: "authorization", Value: "enabled"}}},
		{Key: "sharding", Value: bson.D{{Key: "clusterRole", Value: "shardsvr"}}},
	})
	snap.ServerStatus = mustRaw(t, bson.D{{Key: "host", Value: "db1:27018"}})

	hook := logtest.NewGlobal()
	defer hook.Reset()

	src := &fakeSecuritySource{modeErr: mongo.CommandError{Code: 13, Name: "Unauthorized"}, users: 2}
	s := securitySettings(context.Background(), src, snap, &hostInfo{}, newBudget(time.Minute))
	require.NotNil(t, s)
	assert.Equal(t, "requireTLS", s.SSL)
	assert.Equal(t, int64(27018), s.Port)
	assert.Empty(t, s.WarningMsgs)
	for _, e := range hook.AllEntries() {
		assert.LessOrEqual(t, log.InfoLevel, e.Level, e.Message)
	}

	s = securitySettings(context.Background(), &fakeSecuritySource{mode: "preferTLS"}, snap, &hostInfo{IsLocal: true},
		newBudget(time.Minute))
	require.NotNil(t, s)
	assert.Equal(t, "preferTLS", s.SSL)
	assert.Equal(t, []string{"Warning: You might be insecure (bind ip 8.8.8.8 is public)"}, s.WarningMsgs)

	out, err := formatResults(&collectedInfo{SecuritySettings: s}, "text")
	require.NoError(t, err)
	assert.Equal(t, "\n"+header("Security")+"\n"+
		"Users  : 0\n"+
		"Roles  : 0\n"+
		"Auth   : enabled\n"+
		"SSL    : preferTLS\n"+
		"Port   : 27018\n"+
		"Bind IP: 127.0.0.1,8.8.8.8\n"+
		"Warning: You might be insecure (bind ip 8.8.8.8 is public)\n",
		sectionBetweenHeaders(string(out), "Security"))
}
