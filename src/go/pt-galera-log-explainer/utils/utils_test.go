package utils

import "testing"

func TestStringsReplaceReverse(t *testing.T) {

	tests := []struct {
		inputS     string
		inputOld   string
		inputNew   string
		inputCount int
		expected   string
	}{
		{
			inputS:     "2022-22-22",
			inputOld:   "22",
			inputNew:   "XX",
			inputCount: 1,
			expected:   "2022-22-XX",
		},
		{
			inputS:     "2022-22-22",
			inputOld:   "22",
			inputNew:   "XX",
			inputCount: 2,
			expected:   "2022-XX-XX",
		},
		{
			inputS:     "2022-22-22",
			inputOld:   "22",
			inputNew:   "XX",
			inputCount: 3,
			expected:   "20XX-XX-XX",
		},
	}
	for _, test := range tests {
		if s := StringsReplaceReversed(test.inputS, test.inputOld, test.inputNew, test.inputCount); s != test.expected {
			t.Log("Expected", test.expected, "got", s)
			t.Fail()
		}
	}
}
