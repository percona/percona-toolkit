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

	"go.mongodb.org/mongo-driver/mongo"
)

var externalAuthMechanisms = []string{"GSSAPI", "MONGODB-X509", "PLAIN", "MONGODB-AWS", "MONGODB-OIDC"}

func pingServer(ctx context.Context, client *mongo.Client, b *budget) error {
	var err error
	for attempt := 0; attempt < 2; attempt++ {
		pctx, cancel := b.ctx(ctx, pingTimeout)
		err = client.Ping(pctx, nil)
		cancel()
		if err == nil || isLoginError(err) || b.expired() {
			return err
		}
	}

	return err
}

func isLoginError(err error) bool {
	msg := err.Error()
	return strings.Contains(msg, "auth error") || strings.Contains(msg, "AuthenticationFailed")
}

func connectHint(err error, tlsEnabled bool) string {
	msg := err.Error()
	switch {
	case isLoginError(err):
		return "check --username, --password and --authenticationDatabase: "
	case strings.Contains(msg, "tls:") || strings.Contains(msg, "x509:"):
		return "the TLS handshake failed; check --sslCAFile and --sslPEMKeyFile: "
	case strings.Contains(msg, "EOF") || strings.Contains(msg, "connection reset"):
		if tlsEnabled {
			return "the server closed the connection during the TLS handshake; it may not have TLS enabled, " +
				"or this is not a mongod/mongos port: "
		}
		return "the server closed the connection; it may require TLS (--sslCAFile/--sslPEMKeyFile or tls=true in --uri), " +
			"or this is not a mongod/mongos port: "
	case strings.Contains(msg, "connection refused"):
		return "nothing is listening on that host and port: "
	case strings.Contains(msg, "no such host"):
		return "the host name cannot be resolved: "
	}

	return ""
}

func usesExternalAuth(mechanism string) bool {
	for _, m := range externalAuthMechanisms {
		if strings.EqualFold(mechanism, m) {
			return true
		}
	}

	return false
}
