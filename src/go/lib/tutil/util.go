package tutil

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"gopkg.in/mgo.v2/bson"
)

const (
	updateSamplesEnvVar = "UPDATE_SAMPLES"
)

func RootPath() (string, error) {
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func Pretty(value interface{}) string {
	bytes, _ := json.MarshalIndent(value, "", "    ")
	return string(bytes)
}

func LoadJson(filename string, destination interface{}) error {
	file, err := os.Open(filename)
	if err != nil {
		return err
	}

	buf, err := ioutil.ReadAll(file)
	if err != nil {
		return err
	}

	err = json.Unmarshal(buf, &destination)
	if err != nil {
		return err
	}

	return nil
}

func LoadBson(filename string, destination interface{}) error {
	file, err := os.Open(filename)
	if err != nil {
		return err
	}

	buf, err := ioutil.ReadAll(file)
	if err != nil {
		return err
	}

	// https://github.com/go-mgo/mgo/issues/363
	re := regexp.MustCompile(`" :`)
	buf = re.ReplaceAll(buf, []byte(`":`))

	// Using NumberLong is not supported
	re = regexp.MustCompile(`NumberLong\((.*)\)`)
	buf = re.ReplaceAll(buf, []byte(`$1`))

	// Using regexp is not supported
	// https://github.com/go-mgo/mgo/issues/363
	re = regexp.MustCompile(`(/.*/)`)
	buf = re.ReplaceAll(buf, []byte(`"$1"`))

	// Using functions is not supported
	// https://github.com/go-mgo/mgo/issues/363
	re = regexp.MustCompile(`(?s): (function \(.*?\) {.*?})`)
	buf = re.ReplaceAll(buf, []byte(`: ""`))

	err = bson.UnmarshalJSON(buf, &destination)
	if err != nil {
		return err
	}

	return nil
}

func WriteJson(filename string, data interface{}) error {

	buf, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	err = ioutil.WriteFile(filename, buf, 0777)
	if err != nil {
		return err
	}
	return nil

}

func ShouldUpdateSamples() bool {
	if os.Getenv(updateSamplesEnvVar) != "" {
		return true
	}
	return false
}
