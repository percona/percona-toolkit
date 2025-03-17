package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/spf13/cobra"
)

type MySQLCollector struct {
	stalker  *Stalker
	db       *sql.DB
	outDir   string
	prefix   string
	wg       sync.WaitGroup
	mysqlCfg *MySQLConfig
}

func NewMySQLCollector(config *Config) Collector {
	mysqlCfg := config.CollectorConfigs["mysql"].(*MySQLConfig)
	return &MySQLCollector{
		stalker:  nil,
		db:       nil,
		outDir:   config.Dest,
		prefix:   config.Prefix,
		mysqlCfg: mysqlCfg,
	}
}

func (c *MySQLCollector) Collect(ctx context.Context) error {
	if c.db == nil {
		mysqlCfg := c.mysqlCfg
		dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/", mysqlCfg.User, mysqlCfg.Password, mysqlCfg.Host, mysqlCfg.Port)

		db, err := sql.Open("mysql", dsn)
		if err != nil {
			return fmt.Errorf("failed to connect to MySQL: %v", err)
		}
		c.db = db
		defer db.Close()
	}

	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		c.collectStatus(ctx)
		c.collectVariables(ctx)
		c.collectProcesslist(ctx)
	}()

	c.wg.Wait()
	return nil
}

func (c *MySQLCollector) collectStatus(ctx context.Context) error {
	rows, err := c.db.QueryContext(ctx, "SHOW GLOBAL STATUS")
	if err != nil {
		return err
	}
	defer rows.Close()

	return c.writeResults(rows, c.prefix+"_status.txt")
}

func (c *MySQLCollector) collectVariables(ctx context.Context) error {
	rows, err := c.db.QueryContext(ctx, "SHOW GLOBAL VARIABLES")
	if err != nil {
		return err
	}
	defer rows.Close()

	return c.writeResults(rows, c.prefix+"_variables.txt")
}

func (c *MySQLCollector) collectProcesslist(ctx context.Context) error {
	rows, err := c.db.QueryContext(ctx, "SHOW FULL PROCESSLIST")
	if err != nil {
		return err
	}
	defer rows.Close()

	return c.writeProcesslist(rows, c.prefix+"_processlist.txt")
}

func (c *MySQLCollector) writeResults(rows *sql.Rows, filename string) error {
	f, err := os.Create(filepath.Join(c.outDir, filename))
	if err != nil {
		return err
	}
	defer f.Close()

	for rows.Next() {
		var name, value string
		if err := rows.Scan(&name, &value); err != nil {
			return err
		}
		fmt.Fprintf(f, "%s\t%s\n", name, value)
	}
	return rows.Err()
}

func (c *MySQLCollector) writeProcesslist(rows *sql.Rows, filename string) error {
	f, err := os.Create(filepath.Join(c.outDir, filename))
	if err != nil {
		return err
	}
	defer f.Close()

	for rows.Next() {
		var id, user, host, db, command, time, state, info sql.NullString
		if err := rows.Scan(&id, &user, &host, &db, &command, &time, &state, &info); err != nil {
			return err
		}
		fmt.Fprintf(f, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
			id.String, user.String, host.String, db.String,
			command.String, time.String, state.String, info.String)
	}
	return rows.Err()
}

type MySQLConfig struct {
	Host         string
	Port         int
	User         string
	Password     string
	Socket       string
	DefaultsFile string
}

func addMySQLFlags(cmd *cobra.Command, cfg map[string]interface{}) {
	mysqlCfg := &MySQLConfig{}
	cfg["mysql"] = mysqlCfg

	cmd.PersistentFlags().StringVar(&mysqlCfg.Host, "mysql-host", "", "MySQL host")
	cmd.PersistentFlags().IntVar(&mysqlCfg.Port, "mysql-port", 3306, "MySQL port")
	cmd.PersistentFlags().StringVar(&mysqlCfg.User, "mysql-user", "", "MySQL user")
	cmd.PersistentFlags().StringVar(&mysqlCfg.Password, "mysql-password", "", "MySQL password")
	cmd.PersistentFlags().StringVar(&mysqlCfg.Socket, "mysql-socket", "", "MySQL socket")
	cmd.PersistentFlags().StringVar(&mysqlCfg.DefaultsFile, "mysql-defaults-file", "", "MySQL defaults file")
}

func init() {
	RegisterCollector(CollectorRegistration{
		Name:         "mysql",
		AddFlags:     addMySQLFlags,
		NewCollector: NewMySQLCollector,
	})
}
