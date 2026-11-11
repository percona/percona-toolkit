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
	"strings"
	"testing"
)

func TestParseEnvFile(t *testing.T) {
	const input = `# Written by sandbox-pg/test-env start. Do not edit.
export PG_IPV4_HOST=127.0.0.1
export PG_USERNAME=postgres
export PG_SOURCE_PORT=65432
export PG_REPLICA_PORT=65433
export PG_SOCKET_DIR=
PG_NO_EXPORT_PREFIX=fine

  export PG_INDENTED=yes
`
	got := parseEnvFile(strings.NewReader(input))

	want := map[string]string{
		"PG_IPV4_HOST":        "127.0.0.1",
		"PG_USERNAME":         "postgres",
		"PG_SOURCE_PORT":      "65432",
		"PG_REPLICA_PORT":     "65433",
		"PG_SOCKET_DIR":       "",
		"PG_NO_EXPORT_PREFIX": "fine",
		"PG_INDENTED":         "yes",
	}

	if len(got) != len(want) {
		t.Fatalf("parseEnvFile returned %d keys, want %d: %v", len(got), len(want), got)
	}
	for k, w := range want {
		if g, ok := got[k]; !ok || g != w {
			t.Errorf("parseEnvFile()[%q] = %q (present=%t), want %q", k, g, ok, w)
		}
	}
}

func TestParseEnvFileIgnoresJunk(t *testing.T) {
	const input = `
# a comment = with an equals sign
not a key-value line
export =novalue
`
	got := parseEnvFile(strings.NewReader(input))
	if len(got) != 0 {
		t.Errorf("parseEnvFile returned %v, want no keys", got)
	}
}

func TestResolvePrefersEnvironmentOverFile(t *testing.T) {
	t.Setenv("PG_SOURCE_PORT", "19999")
	if got := resolve("PG_SOURCE_PORT", "65432", "5432"); got != "19999" {
		t.Errorf("resolve = %q, want %q (the process environment must win)", got, "19999")
	}
}

func TestResolvePrefersFileOverDefault(t *testing.T) {
	t.Setenv("PG_SOURCE_PORT", "")
	if got := resolve("PG_SOURCE_PORT", "65432", "5432"); got != "65432" {
		t.Errorf("resolve = %q, want %q (the env file must beat the default)", got, "65432")
	}
}

func TestResolveFallsBackToDefault(t *testing.T) {
	t.Setenv("PG_SOURCE_PORT", "")
	if got := resolve("PG_SOURCE_PORT", "", "5432"); got != "5432" {
		t.Errorf("resolve = %q, want %q", got, "5432")
	}
}

func TestResolveEmptyFileValueFallsBackToEmptyDefault(t *testing.T) {
	t.Setenv("PG_SOCKET_DIR", "")
	if got := resolve("PG_SOCKET_DIR", "", ""); got != "" {
		t.Errorf("resolve = %q, want the empty string", got)
	}
}

func TestEnvFilePathHonoursOverride(t *testing.T) {
	t.Setenv("PT_PG_SANDBOX_ENV", "/somewhere/else/env")
	if got := envFilePath(); got != "/somewhere/else/env" {
		t.Errorf("envFilePath = %q, want %q", got, "/somewhere/else/env")
	}
}

func TestEnvFilePathHonoursTmpDir(t *testing.T) {
	t.Setenv("PT_PG_SANDBOX_ENV", "")
	t.Setenv("TMP_DIR", "/var/tmp")
	if got := envFilePath(); got != "/var/tmp/pt-pg-sandbox/env" {
		t.Errorf("envFilePath = %q, want %q", got, "/var/tmp/pt-pg-sandbox/env")
	}
}
