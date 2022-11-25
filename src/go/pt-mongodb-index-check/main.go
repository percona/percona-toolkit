package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"text/template"
	"time"

	"github.com/alecthomas/kong"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/percona/percona-toolkit/src/go/pt-mongodb-index-check/indexes"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-index-check/templates"
)

type cmdlineArgs struct {
	CheckUnused     struct{} `cmd:"" name:"check-unused" help:"Check for unused indexes."`
	CheckDuplicated struct{} `cmd:"" name:"check-duplicates" help:"Check for duplicated indexes."`
	CheckAll        struct{} `cmd:"" name:"check-all" help:"Check for unused and duplicated indexes."`
	ShowHelp        struct{} `cmd:"" default:"1"`
	Version         struct{} `cmd:"" name:"version"`

	AllDatabases bool     `name:"all-databases" xor:"db" help:"Check in all databases excluding system dbs"`
	Databases    []string `name:"databases" xor:"db" help:"Comma separated list of databases to check"`

	AllCollections bool     `name:"all-collections" xor:"colls" help:"Check in all collections in the selected databases."`
	Collections    []string `name:"collections" xor:"colls" help:"Comma separated list of collections to check"`
	URI            string   `name:"mongodb.uri" required:"" placeholder:"mongodb://host:port/admindb?options" help:"Connection URI"`
	JSON           bool     `name:"json" help:"Show output as JSON"`
}

type response struct {
	Unused     []indexes.IndexStat
	Duplicated []indexes.Duplicate
}

const (
	TOOLNAME = "pt-mongodb-index-check"
)

var (
	Build     string = "2020-04-23" //nolint
	GoVersion string = "1.14.1"     //nolint
	Version   string = "3.5.0"      //nolint
	Commit    string                //nolint
)

func main() {
	var args cmdlineArgs
	kongctx := kong.Parse(&args, kong.UsageOnError())

	if kongctx.Command() == "version" {
		fmt.Println(TOOLNAME)
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	if !strings.HasPrefix(args.URI, "mongodb") && !strings.HasPrefix(args.URI, "mongodb+srv") {
		args.URI = "mongodb://" + args.URI
	}

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(args.URI))
	if err != nil {
		log.Fatalf("Cannot connect to the database: %q", err)
	}

	if args.AllDatabases {
		args.Databases, err = client.ListDatabaseNames(context.TODO(), primitive.D{})
		if err != nil {
			log.Fatalf("cannot list all databases: %s", err)
		}
	}
	if args.AllCollections {
		args.Collections = nil
	}

	resp := response{}

	switch kongctx.Command() {
	case "check-unused":
		resp.Unused = findUnused(ctx, client, args.Databases, args.Collections)
	case "check-duplicates":
		resp.Duplicated = findDuplicated(ctx, client, args.Databases, args.Collections)
	case "check-all":
		resp.Unused = findUnused(ctx, client, args.Databases, args.Collections)
		resp.Duplicated = findDuplicated(ctx, client, args.Databases, args.Collections)
	default:
		kong.DefaultHelpPrinter(kong.HelpOptions{}, kongctx)
	}

	fmt.Println(output(resp, args.JSON))
}

func output(resp response, asJson bool) string {
	if asJson {
		jsonStr, err := json.MarshalIndent(resp, "", "\t")
		if err != nil {
			log.Fatal("cannot encode the response as json")
		}
		return string(jsonStr)
	}

	buf := new(bytes.Buffer)

	t := template.Must(template.New("duplicated").Parse(templates.Duplicated))
	if err := t.Execute(buf, resp.Duplicated); err != nil {
		log.Fatal(errors.Wrap(err, "cannot parse clusterwide section of the output template"))
	}

	t = template.Must(template.New("unused").Parse(templates.Unused))
	if err := t.Execute(buf, resp.Unused); err != nil {
		log.Fatal(errors.Wrap(err, "cannot parse clusterwide section of the output template"))
	}

	return buf.String()
}

func findUnused(ctx context.Context, client *mongo.Client, databases []string, collections []string) []indexes.IndexStat {
	unused := []indexes.IndexStat{}
	var err error

	colls := make([]string, len(collections))
	copy(colls, collections)

	for _, database := range databases {
		if len(collections) == 0 {
			colls, err = client.Database(database).ListCollectionNames(ctx, primitive.D{})
			if err != nil {
				log.Errorf("cannot get the list of collections for the database %s", database)
				continue
			}
		}

		for _, collection := range colls {
			idx, err := indexes.FindUnused(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error while checking unused indexes in %s.%s: %s", database, collection, err)
				continue
			}

			unused = append(unused, idx...)
		}
	}

	return unused
}

func findDuplicated(ctx context.Context, client *mongo.Client, databases []string, collections []string) []indexes.Duplicate {
	duplicated := []indexes.Duplicate{}
	var err error

	colls := make([]string, len(collections))
	copy(colls, collections)

	for _, database := range databases {
		if len(collections) == 0 {
			colls, err = client.Database(database).ListCollectionNames(ctx, primitive.D{})
			if err != nil {
				log.Errorf("cannot get the list of collections for the database %s", database)
				continue
			}
		}

		for _, collection := range colls {
			dups, err := indexes.FindDuplicated(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error while checking duplicated indexes in %s.%s: %s", database, collection, err)
				continue
			}

			duplicated = append(duplicated, dups...)
		}
	}

	return duplicated
}
