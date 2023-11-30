package regex

import (
	"io/ioutil"
	"os/exec"
	"testing"
	"time"

	"github.com/davecgh/go-spew/spew"
	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/pkg/errors"
)

type regexTestState struct {
	State           string
	LogCtx          types.LogCtx
	HashToNodeNames map[string]string
	HashToIP        map[string]string
	IPToMethods     map[string]string
	IPToNodeNames   map[string]string
}

type regexTest struct {
	name                 string
	log, expectedOut     string
	input                regexTestState
	expected             regexTestState
	displayerExpectedNil bool
	expectedErr          bool
	key                  string
}

func iterateRegexTest(t *testing.T, regexmap types.RegexMap, tests []regexTest) {
	utils.SkipColor = true
	for _, test := range tests {
		if test.name == "" {
			test.name = "default"
		}

		// Test 1
		// it's defined in maps
		if _, ok := regexmap[test.key]; !ok {
			t.Fatalf("key %s does not exist in maps", test.key)
		}

		// Add the "input" translations
		// some regexes will react on current state of translations
		translate.ResetDB()
		for hash, nodename := range test.input.HashToNodeNames {
			translate.AddHashToNodeName(hash, nodename, time.Time{})
		}
		for hash, ip := range test.input.HashToIP {
			translate.AddHashToIP(hash, ip, time.Time{})
		}
		for ip, methods := range test.input.IPToMethods {
			translate.AddIPToMethod(ip, methods, time.Time{})
		}
		for ip, nodename := range test.input.IPToNodeNames {
			translate.AddIPToNodeName(ip, nodename, time.Time{})
		}

		// Test 2
		// Launch the test against grep on tmp file
		err := testRegexFromMap(t, test.log, regexmap[test.key])
		if err != nil {
			if test.expectedErr {
				continue
			}
			t.Fatalf("key: %s\ntestname: %s\nregex string: \"%s\"\nlog: %s\n", test.key, test.name, regexmap[test.key].Regex.String(), err)
		}

		if test.input.State != "" {
			test.input.LogCtx.SetState(test.input.State)
		}

		// Test 3
		// Get the message to display using the input context
		logCtx, displayer := regexmap[test.key].Handle(test.input.LogCtx, test.log, time.Time{})
		msg := ""
		if displayer != nil {
			msg = displayer(logCtx)
		} else if !test.displayerExpectedNil {
			t.Errorf("key: %s\ntestname: %s\ndisplayer is nil\nexpected: not nil", test.key, test.name)
		}

		// Test 4
		// Making sure the updated context  is what we expect

		// alternative to reflect.deepequal, it enables to avoid comparing "states" map
		res := cmp.Equal(logCtx, test.expected.LogCtx, cmpopts.IgnoreUnexported(types.LogCtx{}))
		if !res || logCtx.State() != test.expected.State {
			t.Errorf("context is not as expected: \nkey: %s\ntestname: %s\nlogCtx: %+v\nexpected logCtx: %+v\nout: %s\nexpected out: %s\nstate: %s\nexpected state: %s", test.key, test.name, spew.Sdump(logCtx), spew.Sdump(test.expected.LogCtx), msg, test.expectedOut, logCtx.State(), test.expected.State)
			t.Fail()
		}

		// Test 5
		// Making sure the displayed message is correct
		if msg != test.expectedOut {
			t.Errorf("displayed message is not as expected: \nkey: %s\ntestname: %s\nlogCtx: %+v\nout: %s\nexpected out: %s\nstate: %s", test.key, test.name, spew.Sdump(logCtx), msg, test.expectedOut, logCtx.State())
			t.Fail()
		}

		// Test 6
		// Making sure the translations map have the expected values
		// There is a limitation here: "extra" translations stored will not be seen
		maxTime, _ := time.Parse(time.RFC3339, "2100-01-01T01:01:01Z")
		for hash, expectedValue := range test.expected.HashToNodeNames {
			if value := translate.GetNodeNameFromHash(hash, maxTime); value != expectedValue {
				t.Errorf("wrong HashToNodeNames\ntest key: %s\ntestname: %s\nlogCtx: %+v\nout: %s\nhash: %s\nexpectedValue: %s\nvalue: %s", test.key, test.name, spew.Sdump(logCtx), msg, hash, expectedValue, value)
				t.Fail()
			}
		}
		for hash, expectedValue := range test.expected.HashToIP {
			if value := translate.GetIPFromHash(hash); value != expectedValue {
				t.Errorf("wrong HashToIP\ntest key: %s\ntestname: %s\nlogCtx: %+v\nout: %s\nhash: %s\nexpectedValue: %s\nvalue: %s", test.key, test.name, spew.Sdump(logCtx), msg, hash, expectedValue, value)
				t.Fail()
			}
		}
		for ip, expectedValue := range test.expected.IPToMethods {
			if value := translate.GetMethodFromIP(ip, maxTime); value != expectedValue {
				t.Errorf("wrong IPToMethods\ntest key: %s\ntestname: %s\nlogCtx: %+v\nout: %s\nhash: %s\nexpectedValue: %s\nvalue: %s", test.key, test.name, spew.Sdump(logCtx), msg, ip, expectedValue, value)
				t.Fail()
			}
		}
		for ip, expectedValue := range test.expected.IPToNodeNames {
			if value := translate.GetNodeNameFromIP(ip, maxTime); value != expectedValue {
				t.Errorf("wrong IPToNodeNames\ntest key: %s\ntestname: %s\nlogCtx: %+v\nout: %s\nhash: %s\nexpectedValue: %s\nvalue: %s", test.key, test.name, spew.Sdump(logCtx), msg, ip, expectedValue, value)
				t.Fail()
			}
		}
	}
}

func timeMustParse(s string) *time.Time {
	t, _, _ := SearchDateFromLog(s)
	return &t
}

func testRegexFromMap(t *testing.T, log string, regex *types.LogRegex) error {
	m := types.RegexMap{"test": regex}

	return testActualGrepOnLog(t, log, m.Compile()[0])
}

func testActualGrepOnLog(t *testing.T, log, regex string) error {

	f, err := ioutil.TempFile(t.TempDir(), "test_log")
	if err != nil {
		return errors.Wrap(err, "failed to create tmp file")
	}
	defer f.Sync()

	_, err = f.WriteString(log)
	if err != nil {
		return errors.Wrap(err, "failed to write in tmp file")
	}

	out, err := exec.Command("grep", "-P", regex, f.Name()).Output()
	if err != nil {
		return errors.Wrap(err, "failed to grep in tmp file")
	}
	if string(out) == "" {
		return errors.Wrap(err, "empty results when grepping in tmp file")
	}
	return nil
}
