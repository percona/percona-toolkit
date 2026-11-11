// This program is copyright 2020-2026 Percona LLC and/or its affiliates.
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

package dumper

import (
	"testing"
	"time"
)

func TestReserveLocalPort(t *testing.T) {
	t.Run("free port for every pod by default", func(t *testing.T) {
		d := &Dumper{}
		port, release := d.reserveLocalPort()
		defer release()
		if port != "0" {
			t.Fatalf("local port = %q, want %q", port, "0")
		}

		reserved := make(chan struct{})
		go func() {
			_, releaseSecond := d.reserveLocalPort()
			releaseSecond()
			close(reserved)
		}()
		select {
		case <-reserved:
		case <-time.After(5 * time.Second):
			t.Fatal("second reservation waited for the first one")
		}
	})

	t.Run("forwardport is used by one pod at a time", func(t *testing.T) {
		d := &Dumper{forwardport: "18443"}
		port, release := d.reserveLocalPort()
		if port != "18443" {
			release()
			t.Fatalf("local port = %q, want %q", port, "18443")
		}

		reserved := make(chan struct{})
		go func() {
			_, releaseSecond := d.reserveLocalPort()
			close(reserved)
			releaseSecond()
		}()
		select {
		case <-reserved:
			release()
			t.Fatal("second reservation did not wait for the first one")
		case <-time.After(200 * time.Millisecond):
		}

		release()
		select {
		case <-reserved:
		case <-time.After(5 * time.Second):
			t.Fatal("second reservation did not get the port after the first one released it")
		}
	})
}
