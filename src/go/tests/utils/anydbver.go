package utils

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func RunAnyDbVer(args ...string) (string, error) {
	cmd := exec.Command("anydbver", args...)
	output, err := cmd.CombinedOutput()
	outputStr := strings.TrimSpace(string(output))
	if err != nil {
		return outputStr, fmt.Errorf("failed to run anydbver: %s \nOutput: %s", err, outputStr)
	}

	return outputStr, nil
}

func DeployAnyDbVer(args []string) {
	log.Printf("Starting deployment")
	output, err := RunAnyDbVer(args...)
	if err != nil {
		log.Printf("Fail when deploying: %v \nOutput: %s\n", err, output)
		return
	}
	log.Printf("Successfully deployed \nOutput: %s\n", output)
}

func GetKubeConfigString() (string, error) {
	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("failed to get user home directory: %w", err)
		}
		kubeconfig = filepath.Join(home, ".kube", "config")
	}
	return kubeconfig, nil
}

func CleanUpAnyDbVer() error {
	_, err := RunAnyDbVer("destroy")
	if err != nil {
		return fmt.Errorf("cleanup failed: %w", err)
	}
	return nil
}
