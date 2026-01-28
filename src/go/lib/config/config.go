package config

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"os/user"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/alecthomas/kong"
)

// LIB: this will be in lib
type BoolYN bool

func (b *BoolYN) Decode(ctx *kong.DecodeContext, target reflect.Value) error {
	var value string
	err := ctx.Scan.PopValueInto("string", &value) // Читаем как строку, чтобы распарсить вручную
	if err != nil {
		return err
	}

	var result bool
	switch strings.ToLower(value) {
	case "1", "true", "yes", "y", "on", "":
		result = true
	case "0", "false", "no", "n", "off":
		result = false
	default:
		return fmt.Errorf("invalid boolean value %q", value)
	}

	target.SetBool(result)
	return nil
}

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
	if p == nil {
		return nil
	}

	if *p != ASK_PLACEHOLDER {
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

func NewPerconaResolver(r io.Reader) *PerconaResolver {
	res := &PerconaResolver{values: make(map[string]any)}
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		var key, val string
		if strings.Contains(line, "=") {
			parts := strings.SplitN(line, "=", 2)
			key = strings.TrimPrefix(strings.TrimSpace(parts[0]), "--")
			val = strings.Trim(strings.TrimSpace(parts[1]), `"'`)
		} else {
			key = strings.TrimPrefix(line, "--")
			val = "true"
		}

		if strings.HasPrefix(key, "no-") {
			actualKey := strings.TrimPrefix(key, "no-")
			res.values[actualKey] = "false"
		} else {
			res.values[key] = val
		}
	}
	return res
}

func (p *PerconaResolver) Validate(app *kong.Application) error { return nil }
func (p *PerconaResolver) Resolve(ctx *kong.Context, parent *kong.Path, flag *kong.Flag) (any, error) {
	return p.values[flag.Name], nil
}

func loadConfig(path string) (optionsPart io.Reader, passthroughPart []string, err error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, err
	}
	defer f.Close()

	var optsBuffer bytes.Buffer
	var passthrough []string
	scanner := bufio.NewScanner(f)
	foundDash := false

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		if !foundDash && trimmed == "--" {
			foundDash = true
			continue
		}

		if foundDash {
			if trimmed != "" && !strings.HasPrefix(trimmed, "#") {
				passthrough = append(passthrough, strings.Fields(trimmed)...)
			}
		} else {
			optsBuffer.WriteString(line + "\n")
		}
	}
	return &optsBuffer, passthrough, nil
}

func Setup(toolName string, cli any, options ...kong.Option) (*kong.Context, []string, error) {
	rawArgs := os.Args[1:]
	var configPaths []string
	var specifiedConfig bool

	if len(rawArgs) >= 2 && rawArgs[0] == "--config" {
		val := rawArgs[1]
		if val != "''" && val != "" {
			configPaths = strings.Split(val, ",")
		}
		specifiedConfig = true
		rawArgs = rawArgs[2:]
	} else if len(rawArgs) > 0 && strings.HasPrefix(rawArgs[0], "--config") {
		if strings.Contains(rawArgs[0], "=") {
			return nil, nil, fmt.Errorf("Error: --config must not use '='")
		}
	}

	if !specifiedConfig {
		configPaths = getDefaultPaths(toolName)
	}

	var resolvers []kong.Resolver
	var filePassthrough []string

	for _, path := range configPaths {
		optsReader, pass, err := loadConfig(path)
		if err != nil {
			if specifiedConfig {
				return nil, nil, fmt.Errorf("Error: failed to open config %s: %v\n", path, err)
			}
			continue
		}
		resolvers = append(resolvers, NewPerconaResolver(optsReader))
		filePassthrough = append(filePassthrough, pass...)
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

func getDefaultPaths(toolName string) []string {
	u, err := user.Current()
	if err != nil {
		return nil
	}
	return []string{
		"/etc/percona-toolkit/percona-toolkit.conf",
		fmt.Sprintf("/etc/percona-toolkit/%s.conf", toolName),
		filepath.Join(u.HomeDir, ".percona-toolkit.conf"),
		filepath.Join(u.HomeDir, fmt.Sprintf(".%s.conf", toolName)),
	}
}
