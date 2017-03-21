package config

import (
	"fmt"
	"os/user"
	"path"
	"reflect"
	"testing"

	"github.com/percona/percona-toolkit/src/go/lib/tutil"
)

func TestReadConfig(t *testing.T) {

	rootPath, err := tutil.RootPath()
	if err != nil {
		t.Errorf("cannot get root path: %s", err)
	}
	file := path.Join(rootPath, "src/go/tests/lib/sample-config1.conf")

	conf := NewConfig(file)

	keys := []string{"no-version-check", "trueboolvar", "yesboolvar", "noboolvar", "falseboolvar", "intvar", "floatvar", "stringvar"}
	for _, key := range keys {
		if !conf.HasKey(key) {
			t.Errorf("missing %s key", key)
		}
	}

	// no-version-check
	if conf.GetBool("no-version-check") != true {
		t.Error("no-version-check should be enabled")
	}

	// trueboolvar=true
	if conf.GetBool("trueboolvar") != true {
		t.Error("trueboolvar should be true")
	}

	// yesboolvar=yes
	if conf.GetBool("yesboolvar") != true {
		t.Error("yesboolvar should be true")
	}

	// falseboolvar=false
	if conf.GetBool("falseboolvar") != false {
		t.Error("trueboolvar should be false")
	}

	// noboolvar=no
	if conf.GetBool("noboolvar") != false {
		t.Error("yesboolvar should be false")
	}

	// intvar=1
	if got := conf.GetInt64("intvar"); got != 1 {
		t.Errorf("intvar should be 1, got %d", got)
	}

	// floatvar=2.3
	if got := conf.GetFloat64("floatvar"); got != 2.3 {
		t.Errorf("floatvar should be 2.3, got %f", got)
	}

	// stringvar=some string var having = and #
	if got := conf.GetString("stringvar"); got != "some string var having = and #" {
		t.Errorf("string var incorect value; got %s", got)
	}
}

func TestOverrideConfig(t *testing.T) {

	rootPath, err := tutil.RootPath()
	if err != nil {
		t.Errorf("cannot get root path: %s", err)
	}
	file1 := path.Join(rootPath, "src/go/tests/lib/sample-config1.conf")
	file2 := path.Join(rootPath, "src/go/tests/lib/sample-config2.conf")

	conf := NewConfig(file1, file2)

	keys := []string{"no-version-check", "trueboolvar", "yesboolvar", "noboolvar", "falseboolvar", "intvar", "floatvar", "stringvar"}
	for _, key := range keys {
		if !conf.HasKey(key) {
			t.Errorf("missing %s key", key)
		}
	}

	// no-version-check. This option is missing in the 2nd file.
	// It should remain unchanged
	if conf.GetBool("no-version-check") != true {
		t.Error("no-version-check should be enabled")
	}

	if conf.GetBool("trueboolvar") == true {
		t.Error("trueboolvar should be false")
	}

	if conf.GetBool("yesboolvar") == true {
		t.Error("yesboolvar should be false")
	}

	if conf.GetBool("falseboolvar") == false {
		t.Error("trueboolvar should be true")
	}

	if conf.GetBool("noboolvar") == false {
		t.Error("yesboolvar should be true")
	}

	if got := conf.GetInt64("intvar"); got != 4 {
		t.Errorf("intvar should be 4, got %d", got)
	}

	if got := conf.GetFloat64("floatvar"); got != 5.6 {
		t.Errorf("floatvar should be 5.6, got %f", got)
	}

	if got := conf.GetString("stringvar"); got != "some other string" {
		t.Errorf("string var incorect value; got %s", got)
	}

	// This exists only in file2
	if got := conf.GetString("newstring"); got != "a new string" {
		t.Errorf("string var incorect value; got %s", got)
	}

	if got := conf.GetInt64("anotherint"); got != 8 {
		t.Errorf("intvar should be 8, got %d", got)
	}
}

func TestDefaultFiles(t *testing.T) {

	user, _ := user.Current()
	toolname := "pt-testing"

	want := []string{
		"/etc/percona-toolkit/percona-toolkit.conf",
		fmt.Sprintf("/etc/percona-toolkit/%s.conf", toolname),
		fmt.Sprintf("%s/.percona-toolkit.conf", user.HomeDir),
		fmt.Sprintf("%s/.%s.conf", user.HomeDir, toolname),
	}

	got, err := DefaultConfigFiles(toolname)
	if err != nil {
		t.Errorf("cannot get default config files list: %s", err)
	}

	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %#v\nwant: %#v\n", got, want)
	}

}
