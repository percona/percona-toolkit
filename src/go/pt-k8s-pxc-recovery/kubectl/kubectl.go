package kubectl

import (
	"errors"
	"os/exec"
	"runtime"
)

func getKubectl() string {
	switch runtime.GOOS {
	case "windows":
		return "kubectl.exe"
	default:
		return "kubectl"
	}
}

func RunCmd(namespace string, args ...string) (string, error) {
	args = append([]string{"-v=0", "--namespace", namespace}, args...)
	cmd := exec.Command(getKubectl(), args...)
	stdouterr, err := cmd.CombinedOutput()
	if err != nil {
		return "", errors.New(string(stdouterr))
	}
	output := string(stdouterr)
	return output, nil
}
