// This program is copyright 2019-2026 Percona LLC and/or its affiliates.
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

package tu

import (
	"bufio"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const (
	ipv4Host = "127.0.0.1"
	username = "postgres"
	password = "root"

	sourcePort  = "65432"
	replicaPort = "65433"

	tmpDir = "/tmp"

	envFileName = "pt-pg-sandbox/env"
)

var fileVars = loadEnvFile(envFilePath())

var (
	IPv4Host = resolve("PG_IPV4_HOST", fileVars["PG_IPV4_HOST"], ipv4Host)
	Username = resolve("PG_USERNAME", fileVars["PG_USERNAME"], username)
	Password = resolve("PG_PASSWORD", fileVars["PG_PASSWORD"], password)

	SourcePort  = resolve("PG_SOURCE_PORT", fileVars["PG_SOURCE_PORT"], sourcePort)
	ReplicaPort = resolve("PG_REPLICA_PORT", fileVars["PG_REPLICA_PORT"], replicaPort)

	SocketDir = resolve("PG_SOCKET_DIR", fileVars["PG_SOCKET_DIR"], "")
)

func envFilePath() string {
	if p := os.Getenv("PT_PG_SANDBOX_ENV"); p != "" {
		return p
	}
	dir := os.Getenv("TMP_DIR")
	if dir == "" {
		dir = tmpDir
	}
	return filepath.Join(dir, envFileName)
}

func loadEnvFile(path string) map[string]string {
	f, err := os.Open(path)
	if err != nil {
		return map[string]string{}
	}
	defer f.Close()

	return parseEnvFile(f)
}

func parseEnvFile(r io.Reader) map[string]string {
	vars := map[string]string{}

	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")

		key, value, found := strings.Cut(line, "=")
		key = strings.TrimSpace(key)
		if !found || key == "" {
			continue
		}
		vars[key] = strings.TrimSpace(value)
	}

	return vars
}

func resolve(name, fileValue, defaultValue string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	if fileValue != "" {
		return fileValue
	}
	return defaultValue
}
