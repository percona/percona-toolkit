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
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMaxNameLenEmpty(t *testing.T) {
	assert.Equal(t, len("Host"), mongosInfo{}.MaxNameLen())
	assert.Equal(t, len("Host"), mongosInfo{Instances: []mongosInstance{{Name: "a:1"}}}.MaxNameLen())
	assert.Equal(t, len("db-host:47017"), mongosInfo{Instances: []mongosInstance{
		{Name: "a:1"}, {Name: "db-host:47017"}, {Name: "b:2"},
	}}.MaxNameLen())
}

func TestMongosQueryExpiredContext(t *testing.T) {
	ctx, cancel := (&budget{deadline: time.Now().Add(-time.Second)}).ctx(context.Background(), nodeCallTimeout)
	defer cancel()

	_, err := mongoShardingSource{}.mongos(ctx, time.Now())
	require.ErrorIs(t, err, context.DeadlineExceeded)

	reason, _, _ := classifyError(err, false, "find on config.mongos: clusterMonitor")
	assert.Equal(t, "timed out", reason)
}

func TestFindOptionsMaxTime(t *testing.T) {
	t.Run("deadline", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		opts, err := findOptions(ctx)
		require.NoError(t, err)
		require.NotNil(t, opts.MaxTime)
		assert.Positive(t, *opts.MaxTime)
		assert.LessOrEqual(t, *opts.MaxTime, 3*time.Second)
	})

	t.Run("no deadline", func(t *testing.T) {
		opts, err := findOptions(context.Background())
		require.NoError(t, err)
		assert.Nil(t, opts.MaxTime)
	})

	t.Run("expired budget", func(t *testing.T) {
		ctx, cancel := (&budget{deadline: time.Now().Add(-time.Second)}).ctx(context.Background(), nodeCallTimeout)
		defer cancel()

		opts, err := findOptions(ctx)
		require.ErrorIs(t, err, context.DeadlineExceeded)
		assert.Nil(t, opts)
	})
}

func TestFormatMongos(t *testing.T) {
	ping := time.Date(2026, 11, 3, 21, 21, 22, 0, time.UTC)
	ci := &collectedInfo{MongosInfo: &mongosInfo{Instances: []mongosInstance{
		{Name: "a:1", LastPing: ping, UpTime: 5309, Version: "7.0.45-24"},
	}}}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	text := string(out)

	hdr := lineContaining(text, "LastPing")
	row := lineContaining(text, "a:1")
	require.NotEmpty(t, hdr)
	require.NotEmpty(t, row)
	assert.Equal(t, strings.Index(hdr, "LastPing"), strings.Index(row, "2026-11-03T21:21:22Z"))
	assert.Equal(t, strings.Index(hdr, "Version"), strings.Index(row, "7.0.45-24"))
	assert.Equal(t, strings.Index(hdr, "Uptime"), strings.Index(row, "5309"))
}
