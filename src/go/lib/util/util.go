package util

import (
	"encoding/json"
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
