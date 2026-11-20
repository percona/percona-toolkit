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
	"fmt"
	"net"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type security struct {
	Users          int64
	Roles          int64
	Auth           string
	SSL            string
	BindIP         string
	Port           int64
	WarningMsgs    []string
	IsArbiter      bool
	CountsReadable bool
	countsDenied   bool
	countsReason   string
}

func (s *security) CountsDenied() bool {
	return s.countsDenied
}

func (s *security) CountsReason() string {
	return s.countsReason
}

type securitySource interface {
	tlsMode(ctx context.Context) (string, error)
	userRoleCounts(ctx context.Context) (int64, int64, error)
}

type mongoSecuritySource struct {
	client *mongo.Client
}

func (m mongoSecuritySource) tlsMode(ctx context.Context) (string, error) {
	reply, err := runRaw(ctx, m.client, "admin", bson.D{{Key: "getParameter", Value: 1}, {Key: "tlsMode", Value: 1}})
	if err != nil {
		return "", err
	}

	mode, _ := rawString(reply, "tlsMode")

	return mode, nil
}

func (m mongoSecuritySource) userRoleCounts(ctx context.Context) (int64, int64, error) {
	return getUserRolesCount(ctx, m.client)
}

func getSecuritySettings(ctx context.Context, client *mongo.Client, snap *snapshot, hi *hostInfo, b *budget) *security {
	return securitySettings(ctx, mongoSecuritySource{client: client}, snap, hi, b)
}

func securitySettings(ctx context.Context, src securitySource, snap *snapshot, hi *hostInfo, b *budget) *security {
	if hi.IsArbiter && snap.ServerStatusErr != nil {
		return nil
	}

	if snap.CmdLineOpts == nil {
		return nil
	}

	parsed := snap.parsed()
	serverHost, _ := rawString(snap.ServerStatus, "host")
	s := &security{
		Auth:      authMode(parsed),
		BindIP:    effectiveBindIP(parsed),
		Port:      effectivePort(parsed, serverHost, snap.clusterRole()),
		IsArbiter: hi.IsArbiter,
	}

	tctx, cancel := b.ctx(ctx, nodeCallTimeout)
	param, err := src.tlsMode(tctx)
	cancel()
	if err != nil {
		log.Infof("cannot get the runtime tlsMode, using the startup options: %s", err)
	}

	tlsMode, _ := rawString(parsed, "net", "tls", "mode")
	sslMode, _ := rawString(parsed, "net", "ssl", "mode")
	s.SSL = effectiveTLSMode(param, tlsMode, sslMode)

	if hi.IsLocal {
		hostIP, _ := externalIP()
		s.WarningMsgs = bindIPWarnings(s.BindIP, s.Auth == "enabled", hostIP)
	}

	if hi.IsArbiter {
		return s
	}

	cctx, cancel := b.ctx(ctx, nodeCallTimeout)
	defer cancel()

	users, roles, err := src.userRoleCounts(cctx)
	if err != nil {
		const item, needs = "Users/Roles", "find on admin.system.users"

		reason, _, expected := classifyError(err, hi.IsArbiter, needs)
		if strings.HasPrefix(reason, "not authorized") {
			logGap(item, err.Error(), true)
			s.countsDenied = true

			return s
		}

		logGap(item, err.Error(), expected)
		s.countsReason = reason

		return s
	}

	s.Users, s.Roles, s.CountsReadable = users, roles, true

	return s
}

func authMode(parsed bson.Raw) string {
	if transition, _ := rawBool(parsed, "security", "transitionToAuth"); transition {
		return "not enforced (transitionToAuth)"
	}

	if authorization, _ := rawString(parsed, "security", "authorization"); authorization == "enabled" {
		return "enabled"
	}

	if keyFile, _ := rawString(parsed, "security", "keyFile"); keyFile != "" {
		return "enabled"
	}

	switch mode, _ := rawString(parsed, "security", "clusterAuthMode"); mode {
	case "x509", "sendX509", "sendKeyFile":
		return "enabled"
	}

	return "disabled"
}

func effectiveTLSMode(param, tls, ssl string) string {
	for _, mode := range []string{param, tls, ssl} {
		if mode != "" {
			return mode
		}
	}

	return "disabled"
}

func effectivePort(parsed bson.Raw, serverHost, clusterRole string) int64 {
	if port, ok := rawInt64(parsed, "net", "port"); ok {
		return port
	}

	if _, p, err := net.SplitHostPort(serverHost); err == nil {
		if port, err := strconv.ParseInt(p, 10, 64); err == nil {
			return port
		}
	}

	switch clusterRole {
	case "shardsvr":
		return 27018
	case "configsvr":
		return 27019
	}

	return 27017
}

func effectiveBindIP(parsed bson.Raw) string {
	if bindIP, _ := rawString(parsed, "net", "bindIp"); bindIP != "" {
		return bindIP
	}

	return "localhost"
}

func bindIPWarnings(bindIP string, authEnabled bool, hostIP string) []string {
	var msgs []string

	for _, ip := range strings.Split(bindIP, ",") {
		ip = strings.TrimSpace(ip)
		addr := net.ParseIP(ip)
		if ip == "*" {
			addr = net.IPv4zero
		}

		if addr == nil || addr.IsLoopback() {
			continue
		}

		switch {
		case !addr.IsPrivate() && authEnabled:
			msgs = append(msgs, fmt.Sprintf("Warning: You might be insecure (bind ip %s is public)", ip))
		case !addr.IsPrivate():
			msgs = append(msgs, fmt.Sprintf("Error. You are insecure: bind ip %s is public and auth is disabled", ip))
		case ip != hostIP:
			msgs = append(msgs, fmt.Sprintf("WARNING: You might be insecure. IP binding %s is not localhost", ip))
		}
	}

	return msgs
}

func getUserRolesCount(ctx context.Context, client *mongo.Client) (int64, int64, error) {
	users, err := client.Database("admin").Collection("system.users").CountDocuments(ctx, primitive.M{})
	if err != nil {
		return 0, 0, errors.Wrap(err, "cannot get users count")
	}

	roles, err := client.Database("admin").Collection("system.roles").CountDocuments(ctx, primitive.M{})
	if err != nil {
		return 0, 0, errors.Wrap(err, "cannot get roles count")
	}
	return users, roles, nil
}

func externalIP() (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}

	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 {
			continue
		}

		if iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			return "", err
		}

		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}

			if ip == nil || ip.IsLoopback() {
				continue
			}

			ip = ip.To4()
			if ip == nil {
				continue
			}
			return ip.String(), nil
		}
	}

	return "", errors.New("are you connected to the network?")
}
