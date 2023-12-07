package types

import (
	"reflect"
	"testing"
	"time"
)

func TestMergeTimeline(t *testing.T) {

	tests := []struct {
		name     string
		input1   LocalTimeline
		input2   LocalTimeline
		expected LocalTimeline
	}{
		{
			name: "t1 is completely before the t2",
			input1: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
			},
			input2: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
			expected: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
		},
		{
			name: "t1 is completely after the t2",
			input1: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
			input2: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
			},
			expected: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
		},
		{
			name: "t1 is a superset of t2, with same start time",
			input1: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
			input2: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
			},
			// actually what is expected, as we don't expect logs to be different as we already merge them when they are with an identical identifier
			expected: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
		},
		{
			name: "t1 overlap with t2, sharing events",
			input1: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
			input2: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 4, 1, 1, 1, 1, time.UTC)},
				},
			},
			expected: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 4, 1, 1, 1, 1, time.UTC)},
				},
			},
		},

		{
			name: "t1 is completely before the t2, but t2 has null trailing dates",
			input1: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
			},
			input2: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{},
			},
			expected: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{},
			},
		},

		{
			name: "t1 is completely before the t2, but t1 has null leading dates",
			input1: LocalTimeline{
				LogInfo{},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
			},
			input2: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
			expected: LocalTimeline{
				LogInfo{},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 2, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
		},
	}

	for _, test := range tests {
		out := MergeTimeline(test.input1, test.input2)
		if !reflect.DeepEqual(out, test.expected) {
			t.Fatalf("%s failed: expected %v, got %v", test.name, test.expected, out)
		}
	}

}

func TestCutTimelineAt(t *testing.T) {

	tests := []struct {
		name     string
		input1   LocalTimeline
		input2   time.Time
		expected LocalTimeline
	}{
		{
			name: "simple cut",
			input1: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 1, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC)},
				},
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
			input2: time.Date(2023, time.January, 2, 1, 1, 1, 1, time.UTC),
			expected: LocalTimeline{
				LogInfo{
					Date: &Date{Time: time.Date(2023, time.January, 3, 1, 1, 1, 1, time.UTC)},
				},
			},
		},
	}

	for _, test := range tests {
		out := CutTimelineAt(test.input1, test.input2)
		if !reflect.DeepEqual(out, test.expected) {
			t.Fatalf("%s failed: expected %v, got %v", test.name, test.expected, out)
		}
	}

}
