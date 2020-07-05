package helpers

import (
	"log"
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
	args = append([]string{"--namespace", namespace}, args...)
	cmd := exec.Command(getKubectl(), args...)
	// err := cmd.Start()
	// if err != nil {
	// 	log.Fatal(err)
	// }
	err := cmd.Wait()
	if err != nil {
		oerr, _ := cmd.CombinedOutput()
		log.Println(string(oerr))
		log.Fatal(err)
	}
	output, err := cmd.Output()
	if err != nil {
		log.Fatal(err)
	}
	return string(output), nil
}
