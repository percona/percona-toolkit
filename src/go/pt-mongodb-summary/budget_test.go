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

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBudget(t *testing.T) {
	b := newBudget(time.Hour)
	assert.False(t, b.expired())
	assert.InDelta(t, time.Hour, b.remaining(), float64(time.Second))

	ctx, cancel := b.ctx(context.Background(), time.Second)
	defer cancel()
	deadline, ok := ctx.Deadline()
	require.True(t, ok)
	assert.WithinDuration(t, time.Now().Add(time.Second), deadline, 500*time.Millisecond)

	ctx, cancel = b.ctx(context.Background(), b.remaining())
	defer cancel()
	deadline, ok = ctx.Deadline()
	require.True(t, ok)
	assert.WithinDuration(t, b.deadline, deadline, time.Millisecond)

	b = newBudget(time.Second)
	ctx, cancel = b.ctx(context.Background(), time.Hour)
	defer cancel()
	deadline, ok = ctx.Deadline()
	require.True(t, ok)
	assert.Equal(t, b.deadline, deadline)

	b = &budget{deadline: time.Now().Add(-time.Millisecond)}
	assert.True(t, b.expired())
	assert.Zero(t, b.remaining())
	ctx, cancel = b.ctx(context.Background(), time.Hour)
	defer cancel()
	assert.ErrorIs(t, ctx.Err(), context.DeadlineExceeded)

	var unlimited *budget
	assert.False(t, unlimited.expired())
	assert.Greater(t, unlimited.remaining(), 100*365*24*time.Hour)
	ctx, cancel = unlimited.ctx(context.Background(), time.Second)
	defer cancel()
	deadline, ok = ctx.Deadline()
	require.True(t, ok)
	assert.WithinDuration(t, time.Now().Add(time.Second), deadline, 500*time.Millisecond)
}

func TestBudgetSamplingTime(t *testing.T) {
	defaults := &cliOptions{RunningOpsSamples: DefaultRunningOpsSamples, RunningOpsInterval: DefaultRunningOpsInterval}
	assert.Equal(t, 5*time.Second, samplingTime(defaults))
	assert.Equal(t, 28*time.Second, rootBudget+samplingTime(defaults))

	assert.Equal(t, 1500*time.Millisecond, samplingTime(&cliOptions{RunningOpsSamples: 3, RunningOpsInterval: 500}))

	for _, opts := range []*cliOptions{
		{RunningOpsSamples: 0, RunningOpsInterval: 1000},
		{RunningOpsSamples: 5, RunningOpsInterval: 0},
		{RunningOpsSamples: -1, RunningOpsInterval: 1000},
		{RunningOpsSamples: 5, RunningOpsInterval: -1000},
	} {
		assert.Zero(t, samplingTime(opts), "%+v", opts)
	}
}
