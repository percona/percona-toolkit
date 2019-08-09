package explain

import (
	"context"
	"fmt"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

type explain struct {
	ctx    context.Context
	client *mongo.Client
}

func New(ctx context.Context, client *mongo.Client) *explain {
	return &explain{
		ctx:    ctx,
		client: client,
	}
}

func (e *explain) Explain(db string, query []byte) ([]byte, error) {
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

	resultJson, err := bson.MarshalExtJSON(result, true, true)
	if err != nil {
		return nil, fmt.Errorf("explain: unable to encode explain result of %s: %s", string(query), err)
	}

	return resultJson, nil
}
