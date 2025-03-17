package main

import (
	"database/sql"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Common size units for parsing
const (
	_  = iota
	KB = 1 << (10 * iota)
	MB
	GB
	TB
)

// Regular expression for parsing size strings (e.g., "100M", "1.5G")
var sizeRegex = regexp.MustCompile(`^(\d+(?:\.\d+)?)\s*([kKmMgGtT])?[bB]?$`)

// ParseSize converts a human-readable size string to bytes
func ParseSize(size string) (int64, error) {
	matches := sizeRegex.FindStringSubmatch(strings.TrimSpace(size))
	if matches == nil {
		return 0, fmt.Errorf("invalid size format: %s", size)
	}

	value, err := strconv.ParseFloat(matches[1], 64)
	if err != nil {
		return 0, fmt.Errorf("invalid size value: %s", matches[1])
	}

	var multiplier int64 = 1
	if len(matches) > 2 && matches[2] != "" {
		switch strings.ToUpper(matches[2]) {
		case "K":
			multiplier = KB
		case "M":
			multiplier = MB
		case "G":
			multiplier = GB
		case "T":
			multiplier = TB
		}
	}

	return int64(value * float64(multiplier)), nil
}

// FormatSize converts bytes to a human-readable string
func FormatSize(bytes int64) string {
	switch {
	case bytes >= TB:
		return fmt.Sprintf("%.2fTB", float64(bytes)/float64(TB))
	case bytes >= GB:
		return fmt.Sprintf("%.2fGB", float64(bytes)/float64(GB))
	case bytes >= MB:
		return fmt.Sprintf("%.2fMB", float64(bytes)/float64(MB))
	case bytes >= KB:
		return fmt.Sprintf("%.2fKB", float64(bytes)/float64(KB))
	default:
		return fmt.Sprintf("%dB", bytes)
	}
}

// GetDirectorySize calculates the total size of a directory
func GetDirectorySize(path string) (int64, error) {
	var size int64
	err := filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			size += info.Size()
		}
		return nil
	})
	return size, err
}

// IsProcessRunning checks if a process with the given PID is running
func IsProcessRunning(pid int) bool {
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}

	// On Unix systems, FindProcess always succeeds, so we need to send
	// signal 0 to actually check if the process exists
	err = process.Signal(syscall.Signal(0))
	return err == nil
}

// EnsureDirectoryExists creates a directory if it doesn't exist
func EnsureDirectoryExists(path string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return os.MkdirAll(path, 0755)
	}
	return nil
}

// ReadPIDFile reads a PID from a file
func ReadPIDFile(path string) (int, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}

	pid, err := strconv.Atoi(strings.TrimSpace(string(content)))
	if err != nil {
		return 0, fmt.Errorf("invalid PID in file: %v", err)
	}

	return pid, nil
}

// WritePIDFile writes the current process PID to a file
func WritePIDFile(path string) error {
	return os.WriteFile(path, []byte(fmt.Sprintf("%d\n", os.Getpid())), 0644)
}

// CleanOldFiles removes files older than the specified retention time
func CleanOldFiles(dir string, retentionDays int) error {
	if retentionDays <= 0 {
		return nil
	}

	cutoff := time.Now().AddDate(0, 0, -retentionDays)
	return filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if !info.IsDir() && info.ModTime().Before(cutoff) {
			if err := os.Remove(path); err != nil {
				return fmt.Errorf("failed to remove old file %s: %v", path, err)
			}
		}
		return nil
	})
}

// SendEmail sends a notification email
func SendEmail(to, subject, body string) error {
	if to == "" {
		return nil
	}

	cmd := exec.Command("mail", "-s", subject, to)
	cmd.Stdin = strings.NewReader(body)
	return cmd.Run()
}

// GetMySQLProcessID gets the process ID of the MySQL server
func GetMySQLProcessID(db *sql.DB) (int, error) {
	var pid int
	err := db.QueryRow("SELECT @@pid").Scan(&pid)
	if err != nil {
		return 0, fmt.Errorf("failed to get MySQL PID: %v", err)
	}
	return pid, nil
}
