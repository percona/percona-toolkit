package utils

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func RunAnyDbVer(ctx context.Context, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "anydbver", args...)

	var outputBuilder strings.Builder

	stdout := io.MultiWriter(&outputBuilder, os.Stdout)
	stderr := io.MultiWriter(&outputBuilder, os.Stderr)

	cmd.Stdout = stdout
	cmd.Stderr = stderr

	err := cmd.Run()
	outputStr := strings.TrimSpace(outputBuilder.String())

	if err != nil {
		return outputStr, fmt.Errorf("failed to run anydbver: %s \nOutput: %s", err, outputStr)
	}

	return outputStr, nil
}

func DeployAnyDbVer(ctx context.Context, args []string) error {
	log.Printf("Starting deployment")
	output, err := RunAnyDbVer(ctx, args...)
	if err != nil {
		return fmt.Errorf("Fail when deploying: %v \nOutput: %s\n", err, output)
	}
	log.Printf("Successfully deployed \nOutput: %s\n", output)
	return nil
}

func GetKubeConfigPath() (string, error) {
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

func CleanUpAnyDbVer(ctx context.Context) error {
	_, err := RunAnyDbVer(ctx, "destroy")
	if err != nil {
		return fmt.Errorf("cleanup failed: %w", err)
	}
	return nil
}
