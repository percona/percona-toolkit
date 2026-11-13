// This program is copyright 2017-2026 Percona LLC and/or its affiliates.
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

package config

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/user"
	"path"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/percona/percona-toolkit/src/go/lib/tutil"
)

type KongFlags struct {
	ConfigFlag
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

func TestCmdWithArgs(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		cli      any
		wantJson string
	}{
		{
			name: "cmd_one_arg",
			args: []string{"test-cmd", "file.txt"},
			cli: &struct {
				TestCmd struct {
					Paths []string `arg:"" name:"paths"`
				} `cmd:"" name:"test-cmd"`
			}{},
			wantJson: `{"TestCmd":{"Paths":["file.txt"]}}`,
		},
		{
			name: "cmd_one_path_arg",
			args: []string{"test-cmd", "tests/logs/upgrade/node1.log"},
			cli: &struct {
				TestCmd struct {
					Paths []string `arg:"" name:"paths"`
				} `cmd:"" name:"test-cmd"`
			}{},
			wantJson: `{"TestCmd":{"Paths":["tests/logs/upgrade/node1.log"]}}`,
		},
		{
			name: "cmd_many_arg",
			args: []string{"test-cmd", "file.txt", "file2.txt", "file3.txt"},
			cli: &struct {
				TestCmd struct {
					Paths []string `arg:"" name:"paths"`
				} `cmd:"" name:"test-cmd"`
			}{},
			wantJson: `{"TestCmd":{"Paths":["file.txt","file2.txt","file3.txt"]}}`,
		},
	}

	for _, test := range tests {
		os.Args = []string{test.name}
		os.Args = append(os.Args, test.args...)
		_, _, err := Setup(test.name, test.cli)
		if err != nil {
			t.Fatal(err)
		}
		data, err := json.Marshal(test.cli)
		if err != nil {
			t.Fatal(err)
		}
		if string(data) != test.wantJson {
			t.Errorf("got %s, want %s", string(data), test.wantJson)
		}
	}
}

func TestCmdWithArgsAndDefaultConfig(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		cli      any
		config   string
		wantJson string
	}{
		{
			name:   "cmd_one_arg",
			args:   []string{"test-cmd", "file.txt"},
			config: `no-version`,
			cli: &struct {
				TestCmd struct {
					Paths []string `arg:"" name:"paths"`
				} `cmd:"" name:"test-cmd"`
				Version bool `negatable:"" default:"true" name:"version"`
			}{},
			wantJson: `{"TestCmd":{"Paths":["file.txt"]},"Version":false}`,
		},
		{
			name:   "cmd_one_arg",
			args:   []string{"test-cmd", "file.txt"},
			config: `test-list=a,b,c`,
			cli: &struct {
				TestCmd struct {
					Paths []string `arg:"" name:"paths"`
				} `cmd:"" name:"test-cmd"`
				TestList []string `name:"test-list"`
			}{},
			wantJson: `{"TestCmd":{"Paths":["file.txt"]},"TestList":["a","b","c"]}`,
		},
		{
			name: "cmd_one_arg",
			args: []string{"test-cmd", "file.txt"},
			config: `test-list=a,b,c
			limit=123`,
			cli: &struct {
				TestCmd struct {
					Paths []string `arg:"" name:"paths"`
					Limit int      `name:"limit"`
				} `cmd:"" name:"test-cmd"`
				TestList []string `name:"test-list"`
			}{},
			wantJson: `{"TestCmd":{"Paths":["file.txt"],"Limit":123},"TestList":["a","b","c"]}`,
		},
	}

	var oldGlobalDefaultPath = GLOBAL_DEFAULT_PATH
	defer func() {
		GLOBAL_DEFAULT_PATH = oldGlobalDefaultPath
	}()
	for _, test := range tests {
		tmpDir := t.TempDir()
		tmpConf := filepath.Join(tmpDir, "test.conf")
		os.WriteFile(tmpConf, []byte(test.config), 0644)

		GLOBAL_DEFAULT_PATH = tmpConf

		os.Args = []string{test.name}
		os.Args = append(os.Args, test.args...)
		t.Log(os.Args)
		_, _, err := Setup(test.name, test.cli)
		if err != nil {
			t.Fatal(err)
		}
		data, err := json.Marshal(test.cli)
		if err != nil {
			t.Fatal(err)
		}
		if string(data) != test.wantJson {
			t.Errorf("got %s, want %s", string(data), test.wantJson)
		}
	}
}

func TestParseAndValidateConfigFlag(t *testing.T) {
	tests := []struct {
		name             string
		args             []string
		wantPaths        []string
		wantSpecified    bool
		wantRemainingLen int
		wantErr          bool
	}{
		{
			name:          "no_config_flag",
			args:          []string{"--verbose", "--host=localhost"},
			wantPaths:     nil,
			wantSpecified: false,
			wantErr:       false,
		},
		{
			name:          "single_config",
			args:          []string{"--config", "/path/to/config.conf", "--verbose"},
			wantPaths:     []string{"/path/to/config.conf"},
			wantSpecified: true,
			wantErr:       false,
		},
		{
			name:          "multiple_configs",
			args:          []string{"--config", "/etc/config.conf,~/.config.conf", "--verbose"},
			wantPaths:     []string{"/etc/config.conf", "~/.config.conf"},
			wantSpecified: true,
			wantErr:       false,
		},
		{
			name:          "empty_config",
			args:          []string{"--config", "''", "--verbose"},
			wantPaths:     nil,
			wantSpecified: true,
			wantErr:       false,
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
			err := validateConfigPosition(tt.args)
			if err != nil && !tt.wantErr {
				t.Errorf("parseConfigFlag() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			gotPaths, gotSpecified, err := parseConfigFlag(tt.args)

			if err != nil && !tt.wantErr {
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
		})
	}
}

func TestSetupWithConfigFlag(t *testing.T) {
	type TestCLI struct {
		ConfigFlag
		User string `name:"user" default:"guest"`
		Host string `name:"host" default:"localhost"`
	}

	tests := []struct {
		name       string
		args       []string
		globalConf string
		customConf string
		wantUser   string
		wantHost   string
		wantErr    bool
	}{
		{
			name:       "Explicit config overrides default and flags",
			args:       []string{"--config", "CUSTOM_PATH"},
			globalConf: "user=default_user",
			customConf: "user=custom_user\nhost=remote",
			wantUser:   "custom_user",
			wantHost:   "remote",
		},
		{
			name:       "Empty config flag disables all configs",
			args:       []string{"--config", ""},
			globalConf: "user=should_not_be_read",
			customConf: "",
			wantUser:   "guest",
			wantHost:   "localhost",
		},
		{
			name:    "Error if config is not first",
			args:    []string{"--user", "admin", "--config", "some.conf"},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()

			globalPath := filepath.Join(tmpDir, "global.conf")
			os.WriteFile(globalPath, []byte(tt.globalConf), 0644)

			oldGlobal := GLOBAL_DEFAULT_PATH
			GLOBAL_DEFAULT_PATH = globalPath
			defer func() { GLOBAL_DEFAULT_PATH = oldGlobal }()

			args := append([]string{"tool"}, tt.args...)
			for i, arg := range args {
				if arg == "CUSTOM_PATH" {
					customPath := filepath.Join(tmpDir, "custom.conf")
					os.WriteFile(customPath, []byte(tt.customConf), 0644)
					args[i] = customPath
				}
			}

			os.Args = args
			cli := &TestCLI{}

			_, _, err := Setup("test-tool", cli)

			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error but got nil")
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if cli.User != tt.wantUser {
				t.Errorf("User: got %s, want %s", cli.User, tt.wantUser)
			}
			if cli.Host != tt.wantHost {
				t.Errorf("Host: got %s, want %s", cli.Host, tt.wantHost)
			}
		})
	}
}
