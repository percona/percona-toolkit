package explain

import (
	"context"
	"fmt"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

// Explain contains unexported fields of the query explainer
type Explain struct {
	ctx    context.Context
	client *mongo.Client
}

// New returns a new instance of the query explainer
func New(ctx context.Context, client *mongo.Client) *Explain {
	return &Explain{
		ctx:    ctx,
		client: client,
	}
}

// Run runs mongo's explain for the selected database/query
func (e *Explain) Run(db string, query []byte) ([]byte, error) {
	var err error
	var eq proto.ExampleQuery

	err = bson.UnmarshalExtJSON(query, true, &eq)
	if err != nil {
		return nil, fmt.Errorf("explain: unable to decode query %s: %s", string(query), err)
	}

	if db == "" {
		db = eq.Db()
	}

	var result proto.BsonD
	res := e.client.Database(db).RunCommand(e.ctx, eq.ExplainCmd())
	if res.Err() != nil {
		return nil, res.Err()
	}

	if err := res.Decode(&result); err != nil {
		return nil, err
	}

	resultJSON, err := bson.MarshalExtJSON(result, true, true)
	if err != nil {
		return nil, fmt.Errorf("explain: unable to encode explain result of %s: %s", string(query), err)
	}

	return resultJSON, nil
}
