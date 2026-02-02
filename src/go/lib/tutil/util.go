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

package tutil

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"go.mongodb.org/mongo-driver/bson"
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

func LoadBsonold(filename string, destination interface{}) error {
	file, err := os.Open(filename)
	if err != nil {
		return err
	}
	defer file.Close()

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

	re = regexp.MustCompile(`ISODate\((.*)\)`)
	buf = re.ReplaceAll(buf, []byte(`$1`))
	// Using regexp is not supported
	// https://github.com/go-mgo/mgo/issues/363
	re = regexp.MustCompile(`(/.*/)`)
	buf = re.ReplaceAll(buf, []byte(`"$1"`))

	// Using functions is not supported
	// https://github.com/go-mgo/mgo/issues/363
	re = regexp.MustCompile(`(?s): (function \(.*?\) {.*?})`)
	buf = re.ReplaceAll(buf, []byte(`: ""`))

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
	defer file.Close()

	buf, err := ioutil.ReadAll(file)
	if err != nil {
		return err
	}

	err = bson.UnmarshalExtJSON(buf, true, destination)
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
	err = ioutil.WriteFile(filename, buf, 0o777)
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
