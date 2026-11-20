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

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

func rawValue(doc bson.Raw, path ...string) (bson.RawValue, bool) {
	if len(doc) == 0 || len(path) == 0 {
		return bson.RawValue{}, false
	}

	v, err := doc.LookupErr(path...)
	if err != nil {
		return bson.RawValue{}, false
	}

	return v, true
}

func rawString(doc bson.Raw, path ...string) (string, bool) {
	v, ok := rawValue(doc, path...)
	if !ok {
		return "", false
	}

	return v.StringValueOK()
}

func rawInt64(doc bson.Raw, path ...string) (int64, bool) {
	v, ok := rawValue(doc, path...)
	if !ok {
		return 0, false
	}

	if i, ok := v.Int32OK(); ok {
		return int64(i), true
	}

	if i, ok := v.Int64OK(); ok {
		return i, true
	}

	f, ok := v.DoubleOK()
	if !ok || f != math.Trunc(f) || f < math.MinInt64 || f >= -math.MinInt64 {
		return 0, false
	}

	return int64(f), true
}

func rawFloat(doc bson.Raw, path ...string) (float64, bool) {
	v, ok := rawValue(doc, path...)
	if !ok {
		return 0, false
	}

	return numberValue(v)
}

func rawBool(doc bson.Raw, path ...string) (bool, bool) {
	v, ok := rawValue(doc, path...)
	if !ok {
		return false, false
	}

	if b, ok := v.BooleanOK(); ok {
		return b, true
	}

	f, ok := numberValue(v)

	return f != 0, ok
}

func rawDoc(doc bson.Raw, path ...string) (bson.Raw, bool) {
	v, ok := rawValue(doc, path...)
	if !ok {
		return nil, false
	}

	return v.DocumentOK()
}

func rawTime(doc bson.Raw, path ...string) (time.Time, bool) {
	v, ok := rawValue(doc, path...)
	if !ok {
		return time.Time{}, false
	}

	ms, ok := v.DateTimeOK()
	if !ok {
		return time.Time{}, false
	}

	return time.UnixMilli(ms).UTC(), true
}

func rawStrings(doc bson.Raw, path ...string) ([]string, bool) {
	v, ok := rawValue(doc, path...)
	if !ok {
		return nil, false
	}

	arr, ok := v.ArrayOK()
	if !ok {
		return nil, false
	}

	values, err := arr.Values()
	if err != nil {
		return nil, false
	}

	out := make([]string, 0, len(values))
	for _, e := range values {
		if s, ok := e.StringValueOK(); ok {
			out = append(out, s)
		}
	}

	return out, true
}

func numberValue(v bson.RawValue) (float64, bool) {
	if i, ok := v.Int32OK(); ok {
		return float64(i), true
	}

	if i, ok := v.Int64OK(); ok {
		return float64(i), true
	}

	f, ok := v.DoubleOK()
	if !ok || math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, false
	}

	return f, true
}

func runRaw(ctx context.Context, client *mongo.Client, db string, cmd bson.D) (bson.Raw, error) {
	raw, err := client.Database(db).RunCommand(ctx, cmd).Raw()
	if err != nil {
		return nil, err
	}

	return append(bson.Raw(nil), raw...), nil
}
