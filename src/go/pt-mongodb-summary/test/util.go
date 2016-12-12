package test

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func RootDir() (string, error) {
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		rootdir, err := searchDir()
		if err != nil {
			return "", err
		}
		return rootdir, nil
	}
	return strings.Replace(string(out), "\n", "", -1), nil
}

func searchDir() (string, error) {

	rootdir := ""
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}

	for i := 0; i < 3; i++ {
		if FileExists(dir + "/.git") {
			rootdir = filepath.Clean(dir + "test")
			break
		}
		dir = dir + "/.."
	}
	if rootdir == "" {
		return "", fmt.Errorf("cannot detect root dir")
	}
	return rootdir, nil
}

func FileExists(file string) bool {
	_, err := os.Lstat(file)
	if err == nil {
		return true
	}
	if os.IsNotExist(err) {
		return false
	}
	return true
}

func LoadJson(filename string, destination interface{}) error {
	dat, err := ioutil.ReadFile(filename)
	if err != nil {
		return err
	}

	err = json.Unmarshal(dat, &destination)
	if err != nil {
		return err
	}

	return nil
}
