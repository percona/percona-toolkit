package config

import (
	"bufio"
	"os"
	"os/user"
	"strconv"
	"strings"
)

type Config struct {
	options map[string]interface{}
}

func (c *Config) GetString(key string) string {
	if val, ok := c.options[key]; ok {
		if v, ok := val.(string); ok {
			return v
		}
	}
	return ""
}

func (c *Config) GetInt64(key string) int64 {
	if val, ok := c.options[key]; ok {
		if v, ok := val.(int64); ok {
			return v
		}
	}
	return 0
}

func (c *Config) GetFloat64(key string) float64 {
	if val, ok := c.options[key]; ok {
		if v, ok := val.(float64); ok {
			return v
		}
	}
	return 0
}

func (c *Config) GetBool(key string) bool {
	if val, ok := c.options[key]; ok {
		if v, ok := val.(bool); ok {
			return v
		}
	}
	return false
}

func (c *Config) HasKey(key string) bool {
	_, ok := c.options[key]
	return ok
}

func DefaultConfigFiles(toolName string) ([]string, error) {
	user, err := user.Current()
	if err != nil {
		return nil, err
	}

	files := []string{
		"/etc/percona-toolkit/percona-toolkit.conf",
		"/etc/percona-toolkit/${TOOLNAME}.conf",
		"${HOME}/.percona-toolkit.conf",
		"${HOME}/.${TOOLNAME}.conf",
	}

	for i := 0; i < len(files); i++ {
		files[i] = strings.Replace(files[i], "${TOOLNAME}", toolName, -1)
		files[i] = strings.Replace(files[i], "${HOME}", user.HomeDir, -1)
	}

	return files, nil
}

func DefaultConfig(toolname string) *Config {

	files, _ := DefaultConfigFiles(toolname)
	return NewConfig(files...)

}

func NewConfig(files ...string) *Config {
	config := &Config{
		options: make(map[string]interface{}),
	}
	for _, filename := range files {
		if _, err := os.Stat(filename); err == nil {
			read(filename, config.options)
		}
	}
	return config
}

func read(filename string, opts map[string]interface{}) error {

	f, err := os.Open(filename)
	if err != nil {
		return err
	}

	scanner := bufio.NewScanner(f)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		m := strings.SplitN(scanner.Text(), "=", 2)
		key := strings.TrimSpace(m[0])

		if len(m) == 1 {
			opts[key] = true
			continue
		}

		val := strings.TrimSpace(m[1])
		lcval := strings.ToLower(val)

		if lcval == "true" || lcval == "yes" {
			opts[key] = true
			continue
		}
		if lcval == "false" || lcval == "no" {
			opts[key] = false
			continue
		}

		f, err := strconv.ParseFloat(val, 64)
		if err != nil {
			opts[key] = strings.TrimSpace(val) // string
			continue
		}

		if f == float64(int64(f)) {
			opts[key] = int64(f) //int64
			continue
		}

		opts[key] = f // float64
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	return nil
}
