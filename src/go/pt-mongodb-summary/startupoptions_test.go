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
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
)

func parsedOptionsSnapshot(t *testing.T, parsed bson.D) *snapshot {
	t.Helper()

	return &snapshot{CmdLineOpts: mustRaw(t, bson.D{
		{Key: "argv", Value: bson.A{"mongod"}},
		{Key: "parsed", Value: parsed},
		{Key: "ok", Value: 1.0},
	})}
}

func TestMaskOption(t *testing.T) {
	for _, name := range []string{
		"security.kmip.clientCertificatePassword", "setParameter.ldapQueryPassword",
		"net.tls.certificateKeyFilePassword", "net.tls.clusterPassword", "security.vault.secret",
		"setParameter.someApiToken", "x.PASSWD", "kmipClientCertificatePassword", "password",
	} {
		assert.True(t, maskOption(name), name)
	}

	for _, name := range []string{
		"security.kmip.clientCertificateFile", "security.keyFile", "security.vault.tokenFile",
		"net.tls.certificateKeyFile", "security.passwordDigestor", "secret.path", "net.port", "",
	} {
		assert.False(t, maskOption(name), name)
	}

	snap := parsedOptionsSnapshot(t, bson.D{
		{Key: "security", Value: bson.D{{Key: "kmip", Value: bson.D{
			{Key: "serverName", Value: "kmip.example.com"},
			{Key: "clientCertificateFile", Value: "/etc/kmip/client.pem"},
			{Key: "clientCertificatePassword", Value: "s3cr3t"},
		}}}},
		{Key: "setParameter", Value: bson.D{
			{Key: "ldapQueryPassword", Value: "hunter2"},
			{Key: "enableLocalhostAuthBypass", Value: "false"},
		}},
	})

	so := buildStartupOptions(snap)
	require.NotNil(t, so)
	assert.Equal(t, []configOption{
		{Name: "security.kmip.serverName", Value: "kmip.example.com"},
		{Name: "security.kmip.clientCertificateFile", Value: "/etc/kmip/client.pem"},
		{Name: "security.kmip.clientCertificatePassword", Value: "<password>"},
		{Name: "setParameter.ldapQueryPassword", Value: "<password>"},
		{Name: "setParameter.enableLocalhostAuthBypass", Value: "false"},
	}, so.Options)

	ci := &collectedInfo{
		HostInfo: &hostInfo{
			Hostname:    "db1",
			CmdlineArgs: maskArgv([]string{"mongod", "--kmipClientCertificatePassword", "s3cr3t"}),
		},
		StartupOptions: so,
	}

	text, err := formatResults(ci, "text")
	require.NoError(t, err)
	js, err := formatResults(ci, "json")
	require.NoError(t, err)

	for _, out := range [][]byte{text, js} {
		assert.NotContains(t, string(out), "s3cr3t")
		assert.NotContains(t, string(out), "hunter2")
	}
	assert.Contains(t, string(text), "security.kmip.clientCertificatePassword = <password>")
	assert.Contains(t, string(text), "--kmipClientCertificatePassword <password>")

	var decoded collectedInfo
	require.NoError(t, json.Unmarshal(js, &decoded))
	assert.Equal(t, so.Options, decoded.StartupOptions.Options)
	assert.Equal(t, []string{"mongod", "--kmipClientCertificatePassword", "<password>"}, decoded.HostInfo.CmdlineArgs)
}

func TestMaskArgv(t *testing.T) {
	argv := []string{
		"mongod",
		"--kmipClientCertificatePassword", "s3cr3t",
		"--kmipClientCertificatePassword=s3cr3t",
		"--setParameter", "ldapQueryPassword=x",
		"--setParameter=ldapQueryPassword=y",
		"--setParameter", "enableTestCommands=1",
		"--setParameter", "ldapQueryPassword",
		"--ldapQueryPassword=",
		"--tlsCertificateKeyFile", "/p",
		"--tlsCertificateKeyFilePassword", "<password>",
		"--port", "27017",
		"-v",
	}
	orig := append([]string(nil), argv...)

	assert.Equal(t, []string{
		"mongod",
		"--kmipClientCertificatePassword", "<password>",
		"--kmipClientCertificatePassword=<password>",
		"--setParameter", "ldapQueryPassword=<password>",
		"--setParameter=ldapQueryPassword=<password>",
		"--setParameter", "enableTestCommands=1",
		"--setParameter", "ldapQueryPassword",
		"--ldapQueryPassword=<password>",
		"--tlsCertificateKeyFile", "/p",
		"--tlsCertificateKeyFilePassword", "<password>",
		"--port", "27017",
		"-v",
	}, maskArgv(argv))
	assert.Equal(t, orig, argv)

	assert.Equal(t, []string{"mongod", "--ldapQueryPassword"}, maskArgv([]string{"mongod", "--ldapQueryPassword"}))
	assert.Equal(t, []string{"mongod", "--setParameter"}, maskArgv([]string{"mongod", "--setParameter"}))

	assert.Nil(t, maskArgv(nil))
	empty := maskArgv([]string{})
	assert.NotNil(t, empty)
	assert.Empty(t, empty)

	plain := []string{"mongod", "--port", "27017"}
	masked := maskArgv(plain)
	require.Equal(t, plain, masked)
	masked[0] = "changed"
	assert.Equal(t, "mongod", plain[0])
}

func TestStartupOptionsTruncate(t *testing.T) {
	long := strings.Repeat("a", 300)
	so := &startupOptions{Options: []configOption{
		{Name: "setParameter.longValue", Value: long},
		{Name: "net.bindIp", Value: "127.0.0.1"},
		{Name: "setParameter.multiLine", Value: "line1\nline2\x00"},
		{Name: "setParameter.unicode", Value: strings.Repeat("é", 201)},
		{Name: "storage.wiredTiger.engineConfig.configString.withAVeryLongName", Value: "v"},
	}}
	assert.Equal(t, 45, so.NameWidth())
	assert.Equal(t, 10, (&startupOptions{Options: []configOption{{Name: "net.bindIp"}, {Name: "é"}}}).NameWidth())
	assert.Equal(t, 0, (&startupOptions{}).NameWidth())

	ci := &collectedInfo{StartupOptions: so}
	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	text := string(out)

	line := lineContaining(text, "setParameter.longValue")
	assert.Equal(t, "  "+fmt.Sprintf("%-45s", "setParameter.longValue")+" = "+strings.Repeat("a", 200)+"... (300 chars)", line)
	assert.Equal(t, "  "+fmt.Sprintf("%-45s", "net.bindIp")+" = 127.0.0.1", lineContaining(text, "net.bindIp"))
	assert.Equal(t, "  "+fmt.Sprintf("%-45s", "setParameter.multiLine")+` = "line1\nline2\x00"`, lineContaining(text, "multiLine"))
	assert.Equal(t, "  "+fmt.Sprintf("%-45s", "setParameter.unicode")+" = "+strings.Repeat("é", 200)+"... (201 chars)",
		lineContaining(text, "setParameter.unicode"))
	assert.Equal(t, "  storage.wiredTiger.engineConfig.configString.withAVeryLongName = v",
		lineContaining(text, "withAVeryLongName"))

	for _, l := range strings.Split(text, "\n") {
		assert.LessOrEqual(t, len([]rune(l)), 2+64+3+200+len("... (300 chars)"), l)
	}

	js, err := formatResults(ci, "json")
	require.NoError(t, err)

	var decoded collectedInfo
	require.NoError(t, json.Unmarshal(js, &decoded))
	require.NotNil(t, decoded.StartupOptions)
	assert.Equal(t, so.Options, decoded.StartupOptions.Options)
}
