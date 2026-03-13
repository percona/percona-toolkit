// This program is copyright 2017-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package config

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/user"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/alecthomas/kong"
)

// BoolYN represents a boolean flag that accepts multiple textual representations.
// Supported true values: 1, true, yes, y, on, "" (empty)
// Supported false values: 0, false, no, n, off
type BoolYN bool

func (b *BoolYN) Decode(ctx *kong.DecodeContext, target reflect.Value) error {
	var value string
	if err := ctx.Scan.PopValueInto("string", &value); err != nil {
		return err
	}

	var result bool
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "y", "on", "":
		result = true
	case "0", "false", "no", "n", "off":
		result = false
	default:
		return fmt.Errorf("invalid boolean value %q (expected: 1/0, true/false, yes/no, y/n, on/off)", value)
	}

	target.SetBool(result)
	return nil
}

// StdinRequestString represents a string that can be requested from stdin if not provided.
// via Request() method.
type StdinRequestString string

const ASK_PLACEHOLDER = "*"

func (p *StdinRequestString) Decode(ctx *kong.DecodeContext, target reflect.Value) error {
	if ctx.Scan.Len() == 0 {
		target.SetString(ASK_PLACEHOLDER)
		return nil
	}

	var s string
	if err := ctx.Scan.PopValueInto("string", &s); err != nil {
		return err
	}

	target.SetString(s)
	return nil
}

func (p *StdinRequestString) Request(f func() (string, error)) error {
	if p == nil || *p != ASK_PLACEHOLDER {
		return nil
	}

	resp, err := f()
	if err != nil {
		return err
	}

	*p = StdinRequestString(resp)
	return nil
}

type PerconaResolver struct {
	values map[string]any
}

// NewPerconaResolver creates a resolver containing configuration
// in Percona Toolkit format.
//
// Format rules:
//   - Lines starting with # are comments
//   - Empty lines are ignored
//   - Format: "option" or "option=value"
//   - No -- prefix needed
//   - Values are literal (not quoted)
//   - Lines with "no-option" set option to "false"
func NewPerconaResolver(r io.Reader) (*PerconaResolver, error) {
	res := &PerconaResolver{values: make(map[string]any)}

	scanner := bufio.NewScanner(r)
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		var key, val string

		if idx := strings.Index(trimmed, "="); idx != -1 {
			key = strings.TrimSpace(trimmed[:idx])
			val = strings.TrimSpace(trimmed[idx+1:])

			key = strings.TrimPrefix(key, "--")

			if key == "" {
				return nil, fmt.Errorf("line %d: empty option name", lineNum)
			}
		} else {
			key = strings.TrimPrefix(trimmed, "--")
			val = "true"
		}

		if strings.HasPrefix(key, "no-") {
			actualKey := strings.TrimPrefix(key, "no-")
			res.values[actualKey] = "false"
		} else {
			res.values[key] = val
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading config: %w", err)
	}

	return res, nil
}

func (p *PerconaResolver) Validate(app *kong.Application) error {
	return nil
}

func (p *PerconaResolver) Resolve(ctx *kong.Context, parent *kong.Path, flag *kong.Flag) (any, error) {
	return p.values[flag.Name], nil
}

type configFile struct {
	options     io.Reader
	passthrough []string
}

// loadConfig reads a configuration file and splits it into:
// - passthrough arguments (after "--")
func loadConfig(path string) (*configFile, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func() {
		if closeErr := f.Close(); closeErr != nil && err == nil {
			err = closeErr
		}
	}()

	var optsBuffer bytes.Buffer
	var passthrough []string
	scanner := bufio.NewScanner(f)
	foundDash := false
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		if !foundDash && trimmed == "--" {
			foundDash = true
			continue
		}

		if foundDash {
			if trimmed != "" && !strings.HasPrefix(trimmed, "#") {
				fields := strings.Fields(trimmed)
				passthrough = append(passthrough, fields...)
			}
		} else {
			optsBuffer.WriteString(line + "\n")
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading config file: %w", err)
	}

	return &configFile{
		options:     &optsBuffer,
		passthrough: passthrough,
	}, nil
}

// Setup initializes kong parser with Percona Toolkit configuration file support.
//
// It handles:
//   - --config flag as the first argument
//   - Passthrough arguments after "--" in config files
//   - Accepting kong.Options
//
// Returns:
//   - *kong.Context: parsed command-line context
//   - []string: passthrough arguments from config files
//   - error: any error that occurred during setup
func Setup(toolName string, cli any, options ...kong.Option) (*kong.Context, []string, error) {
	rawArgs := os.Args[1:]

	err := validateConfigPosition(rawArgs)
	if err != nil {
		return nil, nil, err
	}

	configPaths, specifiedConfig, err := parseConfigFlag(rawArgs)
	if err != nil {
		return nil, nil, err
	}

	if !specifiedConfig {
		configPaths = getDefaultPaths(toolName)
	}

	resolvers, filePassthrough, err := loadConfigFiles(configPaths, specifiedConfig)
	if err != nil {
		return nil, nil, err
	}

	options = append(options,
		kong.Name(toolName),
		kong.TypeMapper(reflect.TypeOf(BoolYN(false)), new(BoolYN)),
		kong.TypeMapper(reflect.TypeOf(StdinRequestString("")), new(StdinRequestString)),
		kong.Resolvers(resolvers...),
	)

	parser, err := kong.New(cli, options...)
	if err != nil {
		return nil, nil, err
	}

	ctx, err := parser.Parse(rawArgs)
	parser.FatalIfErrorf(err)

	return ctx, filePassthrough, nil
}

func validateConfigPosition(args []string) error {
	if len(args) == 0 {
		return nil
	}

	if args[0] == "--config" {
		return nil
	}

	for i, a := range args {
		if a == "--config" {
			return fmt.Errorf("--config must be the first argument (found at position %d)", i+1)
		}
		if strings.HasPrefix(a, "--config=") {
			return fmt.Errorf("--config must not use '=' syntax. Use: --config file.conf")
		}
	}

	return nil
}

func parseConfigFlag(rawArgs []string) ([]string, bool, error) {
	if len(rawArgs) == 0 {
		return nil, false, nil
	}

	if rawArgs[0] != "--config" {
		return nil, false, nil
	}

	if len(rawArgs) < 2 {
		return nil, false, errors.New("Error: --config requires a value")
	}

	val := rawArgs[1]
	if val == "" || val == "''" || val == `""` {
		return nil, true, nil
	}

	configPaths := strings.Split(val, ",")

	for i := range configPaths {
		configPaths[i] = strings.TrimSpace(configPaths[i])
	}

	return configPaths, true, nil
}

func loadConfigFiles(configPaths []string, specifiedConfig bool) ([]kong.Resolver, []string, error) {
	var resolvers []kong.Resolver
	var filePassthrough []string

	for _, path := range configPaths {
		if path == "" {
			continue
		}

		cfg, err := loadConfig(path)
		if err != nil {
			// If config was explicitly specified, fail on error
			if specifiedConfig {
				return nil, nil, fmt.Errorf("failed to open config %s: %w", path, err)
			}
			// Otherwise, silently skip missing default config files
			continue
		}

		resolver, err := NewPerconaResolver(cfg.options)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to parse config %s: %w", path, err)
		}

		resolvers = append(resolvers, resolver)
		filePassthrough = append(filePassthrough, cfg.passthrough...)
	}

	return resolvers, filePassthrough, nil
}

var GLOBAL_DEFAULT_PATH = "/etc/percona-toolkit/percona-toolkit.conf"

// getDefaultPaths returns the default configuration file paths for a tool.
// Returns paths in order of precedence (lowest to highest):
//  1. /etc/percona-toolkit/percona-toolkit.conf
//  2. /etc/percona-toolkit/TOOL.conf
//  3. $HOME/.percona-toolkit.conf
//  4. $HOME/.TOOL.conf
func getDefaultPaths(toolName string) []string {
	u, err := user.Current()
	if err != nil {
		return []string{
			GLOBAL_DEFAULT_PATH,
			fmt.Sprintf("/etc/percona-toolkit/%s.conf", toolName),
		}
	}

	return []string{
		GLOBAL_DEFAULT_PATH,
		fmt.Sprintf("/etc/percona-toolkit/%s.conf", toolName),
		filepath.Join(u.HomeDir, ".percona-toolkit.conf"),
		filepath.Join(u.HomeDir, fmt.Sprintf(".%s.conf", toolName)),
	}
}
