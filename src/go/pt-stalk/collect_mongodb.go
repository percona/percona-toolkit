package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/spf13/cobra"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type MongoDBCollector struct {
	stalker  *Stalker
	client   *mongo.Client
	outDir   string
	prefix   string
	wg       sync.WaitGroup
	mongoCfg *MongoDBConfig
}

func NewMongoDBCollector(config *Config) Collector {
	mongoCfg := config.CollectorConfigs["mongodb"].(*MongoDBConfig)
	return &MongoDBCollector{
		stalker:  nil,
		client:   nil,
		outDir:   config.Dest,
		prefix:   config.Prefix,
		mongoCfg: mongoCfg,
	}
}

func (c *MongoDBCollector) Collect(ctx context.Context) error {
	if c.client == nil {
		uri := fmt.Sprintf("mongodb://%s:%s@%s:%d",
			c.mongoCfg.User,
			c.mongoCfg.Password,
			c.mongoCfg.Host,
			c.mongoCfg.Port,
		)

		client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
		if err != nil {
			return fmt.Errorf("failed to connect to MongoDB: %v", err)
		}
		c.client = client
		defer client.Disconnect(ctx)
	}

	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		c.collectServerStatus(ctx)
		c.collectCurrentOp(ctx)
		c.collectDatabaseStats(ctx)
	}()

	c.wg.Wait()
	return nil
}

func (c *MongoDBCollector) collectServerStatus(ctx context.Context) error {
	result := bson.M{}
	err := c.client.Database("admin").RunCommand(ctx, bson.D{{Key: "serverStatus", Value: 1}}).Decode(&result)
	if err != nil {
		return err
	}
	return c.writeResults(result, c.prefix+"_server_status.txt")
}

func (c *MongoDBCollector) collectCurrentOp(ctx context.Context) error {
	result := bson.M{}
	err := c.client.Database("admin").RunCommand(ctx, bson.D{{Key: "currentOp", Value: 1}}).Decode(&result)
	if err != nil {
		return err
	}
	return c.writeResults(result, c.prefix+"_current_op.txt")
}

func (c *MongoDBCollector) collectDatabaseStats(ctx context.Context) error {
	dbs, err := c.client.ListDatabaseNames(ctx, bson.D{})
	if err != nil {
		return err
	}

	stats := make(map[string]bson.M)
	for _, dbName := range dbs {
		result := bson.M{}
		err := c.client.Database(dbName).RunCommand(ctx, bson.D{{Key: "dbStats", Value: 1}}).Decode(&result)
		if err != nil {
			return err
		}
		stats[dbName] = result
	}
	return c.writeResults(stats, c.prefix+"_db_stats.txt")
}

func (c *MongoDBCollector) writeResults(data interface{}, filename string) error {
	f, err := os.Create(filepath.Join(c.outDir, filename))
	if err != nil {
		return err
	}
	defer f.Close()

	formatted, err := bson.MarshalExtJSON(data, true, false)
	if err != nil {
		return err
	}

	_, err = f.Write(formatted)
	return err
}

type MongoDBConfig struct {
	Host     string
	Port     int
	User     string
	Password string
}

func addMongoDBFlags(cmd *cobra.Command, cfg map[string]interface{}) {
	mongoCfg := &MongoDBConfig{}
	cfg["mongodb"] = mongoCfg

	cmd.PersistentFlags().StringVar(&mongoCfg.Host, "mongodb-host", "localhost", "MongoDB host")
	cmd.PersistentFlags().IntVar(&mongoCfg.Port, "mongodb-port", 27017, "MongoDB port")
	cmd.PersistentFlags().StringVar(&mongoCfg.User, "mongodb-user", "", "MongoDB user")
	cmd.PersistentFlags().StringVar(&mongoCfg.Password, "mongodb-password", "", "MongoDB password")
}

func init() {
	RegisterCollector(CollectorRegistration{
		Name:         "mongodb",
		AddFlags:     addMongoDBFlags,
		NewCollector: NewMongoDBCollector,
	})
}
