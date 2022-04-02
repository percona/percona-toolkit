package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/alecthomas/kong"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-index-check/indexes"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type cmdlineArgs struct {
	CheckUnused     struct{} `cmd:"" name:"check-unused" help:"Check for unused indexes."`
	CheckDuplicated struct{} `cmd:"" name:"check-duplicates" help:"Check for duplicated indexes."`
	CheckAll        struct{} `cmd:"" name:"check-all" help:"Check for unused and duplicated indexes."`
	ShowHelp        struct{} `cmd:"" default:"1"`

	AllDatabases bool     `name:"all-databases" xor:"db" help:"Check in all databases excluding system dbs"`
	Databases    []string `name:"databases" xor:"db" help:"Comma separated list of databases to check"`

	AllCollections bool     `name:"all-collections" xor:"colls" help:"Check in all collections in the selected databases."`
	Collections    []string `name:"collections" xor:"colls" help:"Comma separated list of collections to check"`
	URI            string   `name:"mongodb.uri" help:"Connection URI"`
}

type response struct {
	Unused     []indexes.IndexStat
	Duplicated []indexes.Duplicate
}

func main() {
	var args cmdlineArgs
	kongctx := kong.Parse(&args, kong.UsageOnError())

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(args.URI))
	if err != nil {
		log.Fatalf("Cannot connect to the database: %q", err)
	}

	resp := response{}

	switch kongctx.Command() {
	case "list-unused":
		for _, database := range args.Databases {
			for _, collection := range args.Collections {
				dups, err = indexes.FindDuplicated(ctx, client, database, collection)
			}
		}
		fmt.Printf("databases: %v\n", args.Databases)
	case "list-duplicates":
	default:
		kong.DefaultHelpPrinter(kong.HelpOptions{}, kongctx)
	}
}
