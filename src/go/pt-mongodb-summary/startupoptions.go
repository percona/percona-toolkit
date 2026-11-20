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
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"go.mongodb.org/mongo-driver/bson"
)

const (
	maskedOptionValue  = "<password>"
	maxOptionNameWidth = 45
	maxOptionValueLen  = 200
)

var secretOptionRE = regexp.MustCompile(`(?i)(password|passwd|secret|token)$`)

type configOption struct {
	Name  string
	Value string
}

type startupOptions struct {
	ConfigFile string
	Options    []configOption
}

func buildStartupOptions(snap *snapshot) *startupOptions {
	if snap.CmdLineOpts == nil {
		return nil
	}

	so := &startupOptions{Options: []configOption{}}
	for _, o := range flattenOptions(snap.parsed()) {
		if o.Name == "config" {
			so.ConfigFile = o.Value

			continue
		}

		so.Options = append(so.Options, o)
	}

	return so
}

func flattenOptions(parsed bson.Raw) []configOption {
	return appendFlatOptions([]configOption{}, "", parsed)
}

func appendFlatOptions(out []configOption, prefix string, doc bson.Raw) []configOption {
	elements, _ := doc.Elements()
	for _, e := range elements {
		name := prefix + e.Key()
		if sub, ok := e.Value().DocumentOK(); ok {
			out = appendFlatOptions(out, name+".", sub)

			continue
		}

		value := startupOptionValue(e.Value())
		if maskOption(name) {
			value = maskedOptionValue
		}

		out = append(out, configOption{Name: name, Value: value})
	}

	return out
}

func startupOptionValue(v bson.RawValue) string {
	switch v.Type {
	case bson.TypeString:
		return v.StringValue()
	case bson.TypeBoolean:
		return strconv.FormatBool(v.Boolean())
	case bson.TypeInt32:
		return strconv.FormatInt(int64(v.Int32()), 10)
	case bson.TypeInt64:
		return strconv.FormatInt(v.Int64(), 10)
	case bson.TypeDouble:
		return strconv.FormatFloat(v.Double(), 'f', -1, 64)
	case bson.TypeArray:
		values, _ := v.Array().Values()
		parts := make([]string, len(values))
		for i, e := range values {
			parts[i] = startupOptionValue(e)
		}

		return strings.Join(parts, ",")
	}

	return v.String()
}

func maskOption(name string) bool {
	return secretOptionRE.MatchString(name)
}

func maskArgv(argv []string) []string {
	if argv == nil {
		return nil
	}

	out := make([]string, len(argv))
	copy(out, argv)

	for i := 0; i < len(out); i++ {
		if !strings.HasPrefix(out[i], "-") {
			continue
		}

		name, value, inline := strings.Cut(strings.TrimLeft(out[i], "-"), "=")
		setParameter := name == "setParameter"
		if !setParameter && !maskOption(name) {
			continue
		}

		switch {
		case inline:
			out[i] = strings.TrimSuffix(out[i], value) + maskArgValue(setParameter, value)
		case i+1 < len(out):
			i++
			out[i] = maskArgValue(setParameter, out[i])
		}
	}

	return out
}

func maskArgValue(setParameter bool, value string) string {
	if !setParameter {
		return maskedOptionValue
	}

	name, _, ok := strings.Cut(value, "=")
	if !ok || !maskOption(name) {
		return value
	}

	return name + "=" + maskedOptionValue
}

func (s *startupOptions) NameWidth() int {
	width := 0
	for _, o := range s.Options {
		width = max(width, utf8.RuneCountInString(o.Name))
	}

	return min(width, maxOptionNameWidth)
}

func (o configOption) TextValue() string {
	v := o.Value
	if strings.ContainsFunc(v, unicode.IsControl) {
		v = strconv.Quote(v)
	}

	if n := utf8.RuneCountInString(v); n > maxOptionValueLen {
		return string([]rune(v)[:maxOptionValueLen]) + fmt.Sprintf("... (%d chars)", n)
	}

	return v
}
