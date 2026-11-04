// This program is copyright 2026 Percona LLC and/or its affiliates.
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

package logparser

import (
	"fmt"
	"math"
	"strconv"
	"strings"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// shellParser parses the documents written by MongoDB <= 4.2 in its plain text logs.
// They use the mongo shell syntax rather than JSON, for example:
//
//	{ find: "orders", filter: { _id: ObjectId('5cd...'), ts: { $gte: new Date(1557829351123) } } }
//
// Values are converted to the closest BSON type. Values that only matter for display
// (UUID, BinData, Timestamp, etc.) are kept as strings.
type shellParser struct {
	s   string
	pos int
}

// parseShellDoc parses the document starting at s[0] and returns it together with the
// number of bytes consumed.
func parseShellDoc(s string) (bson.D, int, error) {
	p := &shellParser{s: s}
	doc, err := p.parseDoc()
	if err != nil {
		return nil, p.pos, err
	}
	return doc, p.pos, nil
}

func (p *shellParser) errorf(format string, args ...interface{}) error {
	return fmt.Errorf("position %d: %s", p.pos, fmt.Sprintf(format, args...))
}

func (p *shellParser) eof() bool {
	return p.pos >= len(p.s)
}

func (p *shellParser) peek() byte {
	if p.eof() {
		return 0
	}
	return p.s[p.pos]
}

func (p *shellParser) skipWS() {
	for !p.eof() {
		switch p.s[p.pos] {
		case ' ', '\t', '\n', '\r':
			p.pos++
		default:
			return
		}
	}
}

func (p *shellParser) expect(c byte) error {
	p.skipWS()
	if p.peek() != c {
		return p.errorf("expected %q", c)
	}
	p.pos++
	return nil
}

func (p *shellParser) parseDoc() (bson.D, error) {
	if err := p.expect('{'); err != nil {
		return nil, err
	}
	doc := bson.D{}
	for {
		p.skipWS()
		if p.peek() == '}' {
			p.pos++
			return doc, nil
		}
		key, err := p.parseKey()
		if err != nil {
			return nil, err
		}
		if err := p.expect(':'); err != nil {
			return nil, err
		}
		p.skipWS()
		value, err := p.parseValue()
		if err != nil {
			return nil, err
		}
		doc = append(doc, bson.E{Key: key, Value: value})

		p.skipWS()
		switch p.peek() {
		case ',':
			p.pos++
		case '}':
		default:
			return nil, p.errorf("expected ',' or '}'")
		}
	}
}

func (p *shellParser) parseArray() (bson.A, error) {
	if err := p.expect('['); err != nil {
		return nil, err
	}
	arr := bson.A{}
	for {
		p.skipWS()
		if p.peek() == ']' {
			p.pos++
			return arr, nil
		}
		value, err := p.parseValue()
		if err != nil {
			return nil, err
		}
		arr = append(arr, value)

		p.skipWS()
		switch p.peek() {
		case ',':
			p.pos++
		case ']':
		default:
			return nil, p.errorf("expected ',' or ']'")
		}
	}
}

func (p *shellParser) parseKey() (string, error) {
	p.skipWS()
	switch p.peek() {
	case '"', '\'':
		return p.parseString()
	}
	start := p.pos
	for !p.eof() {
		switch p.s[p.pos] {
		case ':':
			key := strings.TrimSpace(p.s[start:p.pos])
			if key == "" {
				return "", p.errorf("empty key")
			}
			return key, nil
		case '{', '}', '[', ']', ',', '"', '\'':
			return "", p.errorf("invalid character in key")
		}
		p.pos++
	}
	return "", p.errorf("unexpected end of document")
}

func (p *shellParser) parseString() (string, error) {
	quote := p.peek()
	p.pos++
	var sb strings.Builder
	for !p.eof() {
		c := p.s[p.pos]
		switch {
		case c == '\\' && p.pos+1 < len(p.s):
			p.pos++
			switch e := p.s[p.pos]; e {
			case 'n':
				sb.WriteByte('\n')
			case 't':
				sb.WriteByte('\t')
			case 'r':
				sb.WriteByte('\r')
			default:
				sb.WriteByte(e)
			}
		case c == quote:
			p.pos++
			return sb.String(), nil
		default:
			sb.WriteByte(c)
		}
		p.pos++
	}
	return "", p.errorf("unterminated string")
}

func (p *shellParser) parseValue() (interface{}, error) {
	switch c := p.peek(); {
	case c == '{':
		return p.parseDoc()
	case c == '[':
		return p.parseArray()
	case c == '"' || c == '\'':
		return p.parseString()
	case c == '/':
		return p.parseRegex()
	case c == '-' || c == '+' || c == '.' || (c >= '0' && c <= '9'):
		return p.parseNumber()
	case isIdentStart(c):
		return p.parseIdentValue()
	case c == 0:
		return nil, p.errorf("unexpected end of document")
	default:
		return nil, p.errorf("unexpected character %q", c)
	}
}

func (p *shellParser) parseRegex() (interface{}, error) {
	p.pos++ // opening slash
	var sb strings.Builder
	for {
		if p.eof() {
			return nil, p.errorf("unterminated regex")
		}
		c := p.s[p.pos]
		if c == '\\' && p.pos+1 < len(p.s) {
			sb.WriteByte(c)
			sb.WriteByte(p.s[p.pos+1])
			p.pos += 2
			continue
		}
		p.pos++
		if c == '/' {
			break
		}
		sb.WriteByte(c)
	}
	start := p.pos
	for !p.eof() && isIdentChar(p.s[p.pos]) {
		p.pos++
	}
	return primitive.Regex{Pattern: sb.String(), Options: p.s[start:p.pos]}, nil
}

func (p *shellParser) readToken() string {
	start := p.pos
	for !p.eof() && !isDelimiter(p.s[p.pos]) {
		p.pos++
	}
	return p.s[start:p.pos]
}

func (p *shellParser) parseNumber() (interface{}, error) {
	token := p.readToken()
	if i, err := strconv.ParseInt(token, 10, 64); err == nil {
		if i >= math.MinInt32 && i <= math.MaxInt32 {
			return int32(i), nil
		}
		return i, nil
	}
	if f, err := strconv.ParseFloat(token, 64); err == nil {
		return f, nil
	}
	switch strings.ToLower(token) {
	case "-inf":
		return math.Inf(-1), nil
	case "+inf":
		return math.Inf(1), nil
	}
	if token == "" {
		return nil, p.errorf("empty value")
	}
	return token, nil
}

func (p *shellParser) parseIdentValue() (interface{}, error) {
	start := p.pos
	ident := p.readIdent()

	// "new Date(...)"
	if ident == "new" {
		p.skipWS()
		ident = p.readIdent()
	}

	switch ident {
	case "true":
		return true, nil
	case "false":
		return false, nil
	case "null":
		return nil, nil
	case "undefined":
		return primitive.Undefined{}, nil
	case "MinKey":
		return primitive.MinKey{}, nil
	case "MaxKey":
		return primitive.MaxKey{}, nil
	case "inf", "Infinity":
		return math.Inf(1), nil
	case "nan", "NaN":
		return math.NaN(), nil
	case "function":
		// JavaScript code, as used by mapReduce or $where: function (a, b) { ... }
		if i := strings.IndexByte(p.s[p.pos:], '{'); i >= 0 {
			p.pos += i
			if err := p.skipBalanced('{', '}'); err != nil {
				return nil, err
			}
			return primitive.JavaScript(p.s[start:p.pos]), nil
		}
		return nil, p.errorf("invalid function")
	case "Timestamp":
		// Older versions print timestamps as "Timestamp 1557829351000|1"
		if p.peek() == ' ' && p.pos+1 < len(p.s) && p.s[p.pos+1] >= '0' && p.s[p.pos+1] <= '9' {
			p.pos++
			return "Timestamp " + p.readToken(), nil
		}
	}

	if p.peek() != '(' {
		return ident, nil
	}

	argsStart := p.pos + 1
	if err := p.skipBalanced('(', ')'); err != nil {
		return nil, err
	}
	args := strings.TrimSpace(p.s[argsStart : p.pos-1])
	raw := p.s[start:p.pos]

	switch ident {
	case "ObjectId":
		if oid, err := primitive.ObjectIDFromHex(strings.Trim(args, `'"`)); err == nil {
			return oid, nil
		}
	case "Date":
		if ms, err := strconv.ParseInt(args, 10, 64); err == nil {
			return primitive.DateTime(ms), nil
		}
	case "NumberLong":
		if i, err := strconv.ParseInt(strings.Trim(args, `'"`), 10, 64); err == nil {
			return i, nil
		}
	case "NumberInt":
		if i, err := strconv.ParseInt(strings.Trim(args, `'"`), 10, 32); err == nil {
			return int32(i), nil
		}
	case "NumberDecimal":
		if d, err := primitive.ParseDecimal128(strings.Trim(args, `'"`)); err == nil {
			return d, nil
		}
	}
	return raw, nil
}

func (p *shellParser) readIdent() string {
	start := p.pos
	for !p.eof() && isIdentChar(p.s[p.pos]) {
		p.pos++
	}
	return p.s[start:p.pos]
}

// skipBalanced advances past a balanced open/close block starting at the current position,
// ignoring delimiters inside quoted strings.
func (p *shellParser) skipBalanced(open, close byte) error {
	depth := 0
	for !p.eof() {
		c := p.s[p.pos]
		switch c {
		case '"', '\'':
			if _, err := p.parseString(); err != nil {
				return err
			}
			continue
		case open:
			depth++
		case close:
			depth--
			if depth == 0 {
				p.pos++
				return nil
			}
		}
		p.pos++
	}
	return p.errorf("unbalanced %q", open)
}

func isIdentStart(c byte) bool {
	return c == '_' || c == '$' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func isIdentChar(c byte) bool {
	return isIdentStart(c) || (c >= '0' && c <= '9') || c == '.'
}

func isDelimiter(c byte) bool {
	switch c {
	case ',', '}', ']', ')', ' ', '\t', '\n', '\r':
		return true
	}
	return false
}
