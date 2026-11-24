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
	"math"
	"time"
)

const (
	clientTimeout       = 30 * time.Second
	pingTimeout         = 10 * time.Second
	snapshotCallTimeout = 5 * time.Second
	nodeCallTimeout     = 5 * time.Second
	memberPhaseBudget   = 10 * time.Second
	dbPassBudget        = 5 * time.Second
	ttlWalkBudget       = 5 * time.Second
	rootBudget          = 23 * time.Second
	collectWorkers      = 4
)

type budget struct{ deadline time.Time }

func newBudget(d time.Duration) *budget {
	return &budget{deadline: time.Now().Add(d)}
}

func (b *budget) ctx(parent context.Context, d time.Duration) (context.Context, context.CancelFunc) {
	deadline := time.Now().Add(d)
	if b != nil && b.deadline.Before(deadline) {
		deadline = b.deadline
	}

	return context.WithDeadline(parent, deadline)
}

func (b *budget) expired() bool {
	return b != nil && !time.Now().Before(b.deadline)
}

func (b *budget) remaining() time.Duration {
	if b == nil {
		return math.MaxInt64
	}

	return max(time.Until(b.deadline), 0)
}

func samplingTime(opts *cliOptions) time.Duration {
	if opts.RunningOpsSamples <= 0 || opts.RunningOpsInterval <= 0 {
		return 0
	}

	return time.Duration(opts.RunningOpsSamples) * time.Duration(opts.RunningOpsInterval) * time.Millisecond
}
