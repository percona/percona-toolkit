package config

import (
	"fmt"
	"os"
	"os/user"
	"path"
	"reflect"
	"testing"

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

	got := GetDefaultFiles(toolname)

	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %#v\nwant: %#v\n", got, want)
	}
}
