package utils

import (
	"fmt"
	"strings"
)

// Color is given its own type for safe function signatures
type Color string

// Color codes interpretted by the terminal
// NOTE: all codes must be of the same length or they will throw off the field alignment of tabwriter
const (
	ResetText         Color = "\x1b[0000m"
	BrightText              = "\x1b[0001m"
	RedText                 = "\x1b[0031m"
	GreenText               = "\x1b[0032m"
	YellowText              = "\x1b[0033m"
	BlueText                = "\x1b[0034m"
	MagentaText             = "\x1b[0035m"
	CyanText                = "\x1b[0036m"
	WhiteText               = "\x1b[0037m"
	DefaultText             = "\x1b[0039m"
	BrightRedText           = "\x1b[1;31m"
	BrightGreenText         = "\x1b[1;32m"
	BrightYellowText        = "\x1b[1;33m"
	BrightBlueText          = "\x1b[1;34m"
	BrightMagentaText       = "\x1b[1;35m"
	BrightCyanText          = "\x1b[1;36m"
	BrightWhiteText         = "\x1b[1;37m"
)

var colorsToTextColor = map[string]Color{
	"yellow": YellowText,
	"green":  GreenText,
	"red":    RedText,
}

var SkipColor bool

// Color implements the Stringer interface for interoperability with string
func (c *Color) String() string {
	return string(*c)
}

func Paint(color Color, value string) string {
	if SkipColor {
		return value
	}
	return fmt.Sprintf("%v%v%v", color, value, ResetText)
}

func PaintForState(text, state string) string {

	c := ColorForState(state)
	if c != "" {
		return Paint(colorsToTextColor[c], text)
	}

	return text
}

func ColorForState(state string) string {
	switch state {
	case "DONOR", "JOINER", "DESYNCED":
		return "yellow"
	case "SYNCED":
		return "green"
	case "CLOSED", "NON-PRIMARY":
		return "red"
	default:
		return ""
	}
}

func SliceContains(s []string, str string) bool {
	for _, v := range s {
		if v == str {
			return true
		}
	}
	return false
}

func SliceMergeDeduplicate(s, s2 []string) []string {
	for _, str := range s2 {
		if !SliceContains(s, str) {
			s = append(s, str)
		}
	}
	return s
}

// StringsReplaceReversed is similar to strings.Replace, but replacing the
// right-most elements instead of left-most
func StringsReplaceReversed(s, old, new string, n int) string {

	s2 := s
	stop := len(s)

	for i := 0; i < n; i++ {
		stop = strings.LastIndex(s[:stop], old)

		s2 = (s[:stop]) + new + s2[stop+len(old):]
	}
	return s2
}

func UUIDToShortUUID(uuid string) string {
	splitted := strings.Split(uuid, "-")
	return splitted[0] + "-" + splitted[3]
}

// ShortNodeName helps reducing the node name when it is the default value (node hostname)
// It only keeps the top-level domain
func ShortNodeName(s string) string {
	// short enough
	if len(s) < 10 {
		return s
	}
	before, _, _ := strings.Cut(s, ".")
	return before
}
