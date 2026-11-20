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
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestConnectHint(t *testing.T) {
	tests := []struct {
		name string
		err  string
		tls  bool
		want string
	}{
		{"closed without TLS", "connection(h:1[-1]) socket was unexpectedly closed: EOF", false, "may require TLS"},
		{"reset with TLS", "read tcp 127.0.0.1:1->127.0.0.1:2: read: connection reset by peer", true, "may not have TLS enabled"},
		{"handshake", "tls: first record does not look like a TLS handshake", false, "TLS handshake failed"},
		{"certificate", "x509: certificate signed by unknown authority", true, "TLS handshake failed"},
		{"refused", "dial tcp 127.0.0.1:1: connect: connection refused", false, "nothing is listening"},
		{"dns", "dial tcp: lookup nohost: no such host", false, "cannot be resolved"},
		{"login", "auth error: sasl conversation error: unable to authenticate using mechanism \"SCRAM-SHA-256\": (AuthenticationFailed) Authentication failed.", false, "--authenticationDatabase"},
		{"login before EOF", "auth error: unable to authenticate: EOF", false, "--authenticationDatabase"},
		{"other", "something else", false, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := connectHint(errors.New(tt.err), tt.tls)
			if tt.want == "" {
				assert.Empty(t, got)
				return
			}
			assert.Contains(t, got, tt.want)
		})
	}
}

func TestUsesExternalAuth(t *testing.T) {
	for _, m := range []string{"GSSAPI", "MONGODB-X509", "plain", "MONGODB-AWS", "MONGODB-OIDC"} {
		assert.True(t, usesExternalAuth(m), m)
	}
	for _, m := range []string{"", "SCRAM-SHA-256", "SCRAM-SHA-1"} {
		assert.False(t, usesExternalAuth(m), m)
	}
}

func TestPingServerClosedPort(t *testing.T) {
	client, _ := unreachableClient(t, closedAddr(t), 300*time.Millisecond)
	b := newBudget(5 * time.Second)

	start := time.Now()
	err := pingServer(context.Background(), client, b)

	assert.Error(t, err)
	assert.Less(t, time.Since(start), 2*time.Second)
	assert.Contains(t, connectHint(err, false), "nothing is listening")
}
