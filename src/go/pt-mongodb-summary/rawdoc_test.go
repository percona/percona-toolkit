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
	"math"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

func mustRaw(t *testing.T, v interface{}) bson.Raw {
	t.Helper()

	b, err := bson.Marshal(v)
	require.NoError(t, err)

	return b
}

func TestRawInt64Types(t *testing.T) {
	doc := mustRaw(t, bson.D{
		{Key: "i32", Value: int32(7)},
		{Key: "i64", Value: int64(7)},
		{Key: "double", Value: 7.0},
		{Key: "fraction", Value: 7.5},
		{Key: "huge", Value: 1e19},
		{Key: "nan", Value: math.NaN()},
		{Key: "string", Value: "7"},
		{Key: "a", Value: bson.D{{Key: "b", Value: int32(7)}}},
		{Key: "list", Value: bson.A{int64(7)}},
	})

	for _, key := range []string{"i32", "i64", "double"} {
		v, ok := rawInt64(doc, key)
		assert.True(t, ok, key)
		assert.Equal(t, int64(7), v, key)
	}

	for _, key := range []string{"fraction", "huge", "nan", "string", "missing", "a"} {
		_, ok := rawInt64(doc, key)
		assert.False(t, ok, key)
	}

	v, ok := rawInt64(doc, "a", "b")
	assert.True(t, ok)
	assert.Equal(t, int64(7), v)

	v, ok = rawInt64(doc, "list", "0")
	assert.True(t, ok)
	assert.Equal(t, int64(7), v)

	for _, path := range [][]string{{"a", "missing"}, {"i32", "b"}, {}} {
		_, ok := rawInt64(doc, path...)
		assert.False(t, ok, path)
	}

	_, ok = rawInt64(nil, "i32")
	assert.False(t, ok)
}

func TestRawReaders(t *testing.T) {
	when := time.Date(2026, 10, 27, 18, 11, 40, 0, time.FixedZone("", 2*60*60))
	doc := mustRaw(t, bson.D{
		{Key: "s", Value: "text"},
		{Key: "i32", Value: int32(3)},
		{Key: "i64", Value: int64(4)},
		{Key: "double", Value: 2.5},
		{Key: "nan", Value: math.NaN()},
		{Key: "yes", Value: true},
		{Key: "one", Value: int32(1)},
		{Key: "zero", Value: 0.0},
		{Key: "when", Value: primitive.NewDateTimeFromTime(when)},
		{Key: "ts", Value: primitive.Timestamp{T: 1, I: 1}},
		{Key: "argv", Value: bson.A{"mongod", int32(5), "--port"}},
		{Key: "empty", Value: bson.A{}},
		{Key: "sub", Value: bson.D{{Key: "k", Value: "v"}}},
	})

	s, ok := rawString(doc, "s")
	assert.True(t, ok)
	assert.Equal(t, "text", s)
	_, ok = rawString(doc, "i32")
	assert.False(t, ok)

	for key, want := range map[string]float64{"i32": 3, "i64": 4, "double": 2.5} {
		f, ok := rawFloat(doc, key)
		assert.True(t, ok, key)
		assert.InDelta(t, want, f, 1e-9, key)
	}
	for _, key := range []string{"nan", "s", "missing"} {
		_, ok := rawFloat(doc, key)
		assert.False(t, ok, key)
	}

	for key, want := range map[string]bool{"yes": true, "one": true, "zero": false} {
		b, ok := rawBool(doc, key)
		assert.True(t, ok, key)
		assert.Equal(t, want, b, key)
	}
	_, ok = rawBool(doc, "s")
	assert.False(t, ok)

	sub, ok := rawDoc(doc, "sub")
	assert.True(t, ok)
	s, _ = rawString(sub, "k")
	assert.Equal(t, "v", s)
	_, ok = rawDoc(doc, "s")
	assert.False(t, ok)

	tm, ok := rawTime(doc, "when")
	assert.True(t, ok)
	assert.Equal(t, time.UTC, tm.Location())
	assert.True(t, tm.Equal(when))
	_, ok = rawTime(doc, "ts")
	assert.False(t, ok)

	argv, ok := rawStrings(doc, "argv")
	assert.True(t, ok)
	assert.Equal(t, []string{"mongod", "--port"}, argv)

	empty, ok := rawStrings(doc, "empty")
	assert.True(t, ok)
	assert.NotNil(t, empty)
	assert.Empty(t, empty)

	_, ok = rawStrings(doc, "s")
	assert.False(t, ok)
	_, ok = rawStrings(nil, "argv")
	assert.False(t, ok)
}
