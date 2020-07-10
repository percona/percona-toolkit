package helpers

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"runtime"
)

var namespace = ""

func getKubectl() string {
	switch runtime.GOOS {
	case "windows":
		return "kubectl.exe"
	default:
		return "kubectl"
	}
}

func SetNamespace(name string) {
	if namespace == "" {
		namespace = name
	}
}

func RunCmd(args ...string) (string, error) {
	args = append([]string{"-v=0", "--namespace", namespace}, args...)
	cmd := exec.Command(getKubectl(), args...)
	cmd.Env = os.Environ()
	println(cmd.String())
	stdouterr, err := cmd.CombinedOutput()
	if err != nil {
		return "", errors.New(string(stdouterr))
	}
	output := string(stdouterr)
	fmt.Println(output)
	return output, nil
}
