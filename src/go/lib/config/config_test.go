package config

import (
	"bytes"
	"fmt"
	"os"
	"os/user"
	"path"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/alecthomas/kong"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
)

type KongFlags struct {
	VersionCheck   bool    `name:"version-check" negatable:"" default:"true"`
	TrueBoolVar    bool    `name:"trueboolvar" help:"test"`
	YesBoolVar     BoolYN  `name:"yesboolvar" help:"test"`
	FalseBoolVar   bool    `name:"falseboolvar" help:"test"`
	NoBoolVar      BoolYN  `name:"noboolvar" help:"test"`
	IntVar         int     `name:"intvar" default:"0"`
	FloatVar       float64 `name:"floatvar" default:"0.0"`
	StringVar      string  `name:"stringvar"`
	NewString      string  `name:"newstring" short:"n"`
	AnotherInt     int     `name:"anotherint" default:"0" short:"a"`
	IgnoredComment string  `name:"ignoredcomment"`
}

func TestReadConfigKong(t *testing.T) {
	rootPath, err := tutil.RootPath()
	if err != nil {
		t.Errorf("cannot get root path: %s", err)
	}
	file := path.Join(rootPath, "src/go/tests/lib/sample-config1.conf")

	var mockArgs []string

	mockArgs = append(mockArgs, os.Args[0])

	mockArgs = append(mockArgs, []string{"--config", file}...)
	os.Args = mockArgs

	f := &KongFlags{}
	toolName := "pt-tools-config-test"

	_, _, err = Setup(toolName, f)
	if err != nil {
		t.Error(err)
	}

	// no-version-check
	if f.VersionCheck {
		t.Error("no-version-check should be enabled")
	}

	// trueboolvar=true
	if !f.TrueBoolVar {
		t.Error("trueboolvar should be true")
	}

	// yesboolvar=yes
	if !f.YesBoolVar {
		t.Error("yesboolvar should be true")
	}

	// falseboolvar=false
	if f.FalseBoolVar {
		t.Error("trueboolvar should be false")
	}

	// noboolvar=no
	if f.NoBoolVar {
		t.Error("yesboolvar should be false")
	}

	// intvar=1
	if f.IntVar != 1 {
		t.Errorf("intvar should be 1, got %d", f.IntVar)
	}

	// floatvar=2.3
	if f.FloatVar != 2.3 {
		t.Errorf("floatvar should be 2.3, got %f", f.FloatVar)
	}

	// stringvar=some string var having = and #
	if f.StringVar != "some string var having = and #" {
		t.Errorf("string var incorrect value; got %q", f.StringVar)
	}

	if f.IgnoredComment != "" {
		t.Errorf("ignoredcomment should be empty; got %q", f.IgnoredComment)
	}
}

func TestOverrideConfigKong(t *testing.T) {
	rootPath, err := tutil.RootPath()
	if err != nil {
		t.Errorf("cannot get root path: %s", err)
	}
	file1 := path.Join(rootPath, "src/go/tests/lib/sample-config1.conf")
	file2 := path.Join(rootPath, "src/go/tests/lib/sample-config2.conf")

	var mockArgs []string

	mockArgs = append(mockArgs, os.Args[0])

	mockArgs = append(mockArgs, []string{"--config", fmt.Sprintf("%s,%s", file1, file2)}...)
	os.Args = mockArgs

	f := &KongFlags{}
	toolName := "pt-tools-config-test"

	_, _, err = Setup(toolName, f)
	if err != nil {
		t.Error(err)
	}

	// no-version-check. This option is missing in the 2nd file.
	// It should remain unchanged
	if f.VersionCheck {
		t.Error("no-version-check should be enabled")
	}

	if f.TrueBoolVar {
		t.Error("trueboolvar should be false")
	}

	if f.YesBoolVar {
		t.Error("yesboolvar should be false")
	}

	if !f.FalseBoolVar {
		t.Error("trueboolvar should be true")
	}

	if !f.NoBoolVar {
		t.Error("yesboolvar should be true")
	}

	if f.IntVar != 4 {
		t.Errorf("intvar should be 4, got %d", f.IntVar)
	}

	if f.FloatVar != 5.6 {
		t.Errorf("floatvar should be 5.6, got %f", f.FloatVar)
	}

	if f.StringVar != "some other string" {
		t.Errorf("string var incorrect value; got %s", f.StringVar)
	}

	// This exists only in file2
	if f.NewString != "a new string" {
		t.Errorf("string var incorrect value; got %s", f.NewString)
	}

	if f.AnotherInt != 8 {
		t.Errorf("intvar should be 8, got %d", f.AnotherInt)
	}

	if f.IgnoredComment != "" {
		t.Errorf("ignoredcomment should be empty; got %q", f.IgnoredComment)
	}
}

func TestOverrideCMDConfigKong(t *testing.T) {
	rootPath, err := tutil.RootPath()
	if err != nil {
		t.Errorf("cannot get root path: %s", err)
	}
	file1 := path.Join(rootPath, "src/go/tests/lib/sample-config1.conf")

	var mockArgs []string

	mockArgs = append(mockArgs, os.Args[0])

	mockArgs = append(mockArgs,
		"--config", file1,
		"--trueboolvar=false", // reset bool flag
		"--yesboolvar", "no",
		"--falseboolvar=true", // reset bool flag
		"--noboolvar", "yes",
		"--intvar", "1337",
		"--floatvar", "1337.1",
		"--stringvar", "hello",
		"-n", "world", // test shorthand
		"-a", "3", // test shorthand
	)
	os.Args = mockArgs

	f := &KongFlags{}
	toolName := "pt-tools-config-test"

	_, _, err = Setup(toolName, f)
	if err != nil {
		t.Error(err)
	}

	if f.VersionCheck {
		t.Error("no-version-check should be enabled")
	}

	if f.TrueBoolVar {
		t.Error("trueboolvar should be false")
	}

	if f.YesBoolVar {
		t.Error("yesboolvar should be false")
	}

	if !f.FalseBoolVar {
		t.Error("trueboolvar should be true")
	}

	if !f.NoBoolVar {
		t.Error("yesboolvar should be true")
	}

	if f.IntVar != 1337 {
		t.Errorf("intvar should be 1337, got %d", f.IntVar)
	}

	if f.FloatVar != 1337.1 {
		t.Errorf("floatvar should be 1337.1, got %f", f.FloatVar)
	}

	if f.StringVar != "hello" {
		t.Errorf("string var incorrect value; got %s", f.StringVar)
	}

	// This exists only in file2
	if f.NewString != "world" {
		t.Errorf("string var incorrect value; got %s", f.NewString)
	}

	if f.AnotherInt != 3 {
		t.Errorf("intvar should be 3, got %d", f.AnotherInt)
	}

	if f.IgnoredComment != "" {
		t.Errorf("ignoredcomment should be empty; got %q", f.IgnoredComment)
	}
}

func TestDefaultFilesKong(t *testing.T) {
	current, _ := user.Current()
	toolname := "pt-testing"

	want := []string{
		"/etc/percona-toolkit/percona-toolkit.conf",
		fmt.Sprintf("/etc/percona-toolkit/%s.conf", toolname),
		fmt.Sprintf("%s/.percona-toolkit.conf", current.HomeDir),
		fmt.Sprintf("%s/.%s.conf", current.HomeDir, toolname),
	}

	got := getDefaultPaths(toolname)

	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %#v\nwant: %#v\n", got, want)
	}
}

func TestNewPerconaResolver(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    map[string]any
		wantErr bool
	}{
		{
			name: "basic_options",
			input: `# Comment
variable=Threads_connected
cycles=2
verbose`,
			want: map[string]any{
				"variable": "Threads_connected",
				"cycles":   "2",
				"verbose":  "true",
			},
			wantErr: false,
		},
		{
			name: "with_no_prefix",
			input: `option=value
no-optimize`,
			want: map[string]any{
				"option":   "value",
				"optimize": "false",
			},
			wantErr: false,
		},
		{
			name: "with_double_dash_prefix", // Not valid according to specs but should pass
			input: `--host=localhost
--port=3306`,
			want: map[string]any{
				"host": "localhost",
				"port": "3306",
			},
			wantErr: false,
		},
		{
			name:  "empty_lines_and_comments",
			input: "\n# Comment\n\n# Another comment\n\noption=value\n\n",
			want: map[string]any{
				"option": "value",
			},
			wantErr: false,
		},
		{
			name: "spaces_around_equals", // Not valid according to specs but should pass
			input: `key = value
another=test`,
			want: map[string]any{
				"key":     "value",
				"another": "test",
			},
			wantErr: false,
		},
		{
			name:    "invalid_empty_key",
			input:   `=value`,
			want:    nil,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			reader := strings.NewReader(tt.input)
			got, err := NewPerconaResolver(reader)

			if (err != nil) != tt.wantErr {
				t.Errorf("NewPerconaResolver() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if tt.wantErr {
				return
			}

			if !reflect.DeepEqual(got.values, tt.want) {
				t.Errorf("NewPerconaResolver() values = %v, want %v", got.values, tt.want)
			}
		})
	}
}

func TestLoadConfig(t *testing.T) {
	tests := []struct {
		name            string
		content         string
		wantOptions     string
		wantPassthrough []string
		wantErr         bool
	}{
		{
			name: "basic_config",
			content: `variable=Threads_connected
cycles=2`,
			wantOptions: `variable=Threads_connected
cycles=2
`,
			wantPassthrough: nil,
			wantErr:         false,
		},
		{
			name: "with_passthrough",
			content: `variable=Threads_connected
cycles=2
--
--user daniel
--password secret`,
			wantOptions: `variable=Threads_connected
cycles=2
`,
			wantPassthrough: []string{"--user", "daniel", "--password", "secret"},
			wantErr:         false,
		},
		{
			name: "passthrough_with_comments",
			content: `option=value
--
# This is a comment
--user root
# Another comment
--host localhost`,
			wantOptions: `option=value
`,
			wantPassthrough: []string{"--user", "root", "--host", "localhost"},
			wantErr:         false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create temp file
			tmpDir := t.TempDir()
			tmpFile := filepath.Join(tmpDir, "test.conf")
			if err := os.WriteFile(tmpFile, []byte(tt.content), 0644); err != nil {
				t.Fatalf("Failed to create temp file: %v", err)
			}

			got, err := loadConfig(tmpFile)
			if (err != nil) != tt.wantErr {
				t.Errorf("loadConfig() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if tt.wantErr {
				return
			}

			// Check options
			var buf bytes.Buffer
			if _, err := buf.ReadFrom(got.options); err != nil {
				t.Fatalf("Failed to read options: %v", err)
			}
			if buf.String() != tt.wantOptions {
				t.Errorf("loadConfig() options = %q, want %q", buf.String(), tt.wantOptions)
			}

			// Check passthrough
			if !reflect.DeepEqual(got.passthrough, tt.wantPassthrough) {
				t.Errorf("loadConfig() passthrough = %v, want %v", got.passthrough, tt.wantPassthrough)
			}
		})
	}
}

func TestParseConfigFlag(t *testing.T) {
	tests := []struct {
		name             string
		args             []string
		wantPaths        []string
		wantSpecified    bool
		wantRemainingLen int
		wantErr          bool
	}{
		{
			name:             "no_config_flag",
			args:             []string{"--verbose", "--host=localhost"},
			wantPaths:        nil,
			wantSpecified:    false,
			wantRemainingLen: 2,
			wantErr:          false,
		},
		{
			name:             "single_config",
			args:             []string{"--config", "/path/to/config.conf", "--verbose"},
			wantPaths:        []string{"/path/to/config.conf"},
			wantSpecified:    true,
			wantRemainingLen: 1,
			wantErr:          false,
		},
		{
			name:             "multiple_configs",
			args:             []string{"--config", "/etc/config.conf,~/.config.conf", "--verbose"},
			wantPaths:        []string{"/etc/config.conf", "~/.config.conf"},
			wantSpecified:    true,
			wantRemainingLen: 1,
			wantErr:          false,
		},
		{
			name:             "empty_config",
			args:             []string{"--config", "''", "--verbose"},
			wantPaths:        nil,
			wantSpecified:    true,
			wantRemainingLen: 1,
			wantErr:          false,
		},
		{
			name:      "config_with_equals",
			args:      []string{"--config=/path/to/config.conf"},
			wantPaths: nil,
			wantErr:   true,
		},
		{
			name:      "config_without_value",
			args:      []string{"--config"},
			wantPaths: nil,
			wantErr:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotPaths, gotSpecified, gotRemaining, err := parseConfigFlag(tt.args)

			if (err != nil) != tt.wantErr {
				t.Errorf("parseConfigFlag() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if tt.wantErr {
				return
			}

			if !reflect.DeepEqual(gotPaths, tt.wantPaths) {
				t.Errorf("parseConfigFlag() paths = %v, want %v", gotPaths, tt.wantPaths)
			}

			if gotSpecified != tt.wantSpecified {
				t.Errorf("parseConfigFlag() specified = %v, want %v", gotSpecified, tt.wantSpecified)
			}

			if len(gotRemaining) != tt.wantRemainingLen {
				t.Errorf("parseConfigFlag() remaining len = %d, want %d", len(gotRemaining), tt.wantRemainingLen)
			}
		})
	}
}

type mockScanner struct {
	value    string
	hasValue bool
}

func (m *mockScanner) Len() int {
	if m.hasValue {
		return 1
	}
	return 0
}

func (m *mockScanner) PopValueInto(name string, target interface{}) error {
	if !m.hasValue {
		return fmt.Errorf("no value set")
	}
	if s, ok := target.(*string); ok {
		*s = m.value
		return nil
	}
	return fmt.Errorf("scanner error")
}

// Additional mock methods required by kong.Scanner interface
func (m *mockScanner) Pop() *kong.Token                   { return nil }
func (m *mockScanner) Peek() *kong.Token                  { return nil }
func (m *mockScanner) PushTyped(interface{}, *kong.Token) {}
