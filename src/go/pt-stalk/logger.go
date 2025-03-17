package main

import (
	"fmt"
	"log"
	"os"
	"time"
)

type Logger struct {
	logger   *log.Logger
	verbose  int
	filename string
}

func NewLogger(filename string, verbose int) (*Logger, error) {
	var output *os.File
	var err error

	if filename == "" || filename == "-" {
		output = os.Stdout
	} else {
		output, err = os.OpenFile(filename, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			return nil, fmt.Errorf("failed to open log file: %v", err)
		}
	}

	return &Logger{
		logger:   log.New(output, "", 0),
		verbose:  verbose,
		filename: filename,
	}, nil
}

func (l *Logger) formatMessage(level string, format string, args ...interface{}) string {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	message := fmt.Sprintf(format, args...)
	return fmt.Sprintf("%s [%s] %s", timestamp, level, message)
}

func (l *Logger) Error(format string, args ...interface{}) {
	if l.verbose >= 0 {
		l.logger.Println(l.formatMessage("ERROR", format, args...))
	}
}

func (l *Logger) Warn(format string, args ...interface{}) {
	if l.verbose >= 1 {
		l.logger.Println(l.formatMessage("WARN", format, args...))
	}
}

func (l *Logger) Info(format string, args ...interface{}) {
	if l.verbose >= 2 {
		l.logger.Println(l.formatMessage("INFO", format, args...))
	}
}

func (l *Logger) Debug(format string, args ...interface{}) {
	if l.verbose >= 3 {
		l.logger.Println(l.formatMessage("DEBUG", format, args...))
	}
}

func (l *Logger) Close() error {
	if l.filename != "" && l.filename != "-" {
		if logger, ok := l.logger.Writer().(*os.File); ok {
			return logger.Close()
		}
	}
	return nil
}
