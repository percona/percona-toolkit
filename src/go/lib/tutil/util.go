package tutil

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"os/exec"
	"strings"
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

func WriteJson(filename string, data interface{}) error {

	buf, err := json.Marshal(data)
	if err != nil {
		return err
	}
	err = ioutil.WriteFile(filename, buf, 0)
	if err != nil {
		return err
	}
	return nil

}
