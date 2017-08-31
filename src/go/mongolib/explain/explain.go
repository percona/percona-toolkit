package explain

import (
	"fmt"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"
	"gopkg.in/mgo.v2/bson"
)

type explain struct {
	session pmgo.SessionManager
}

func New(session pmgo.SessionManager) *explain {
	return &explain{
		session: session,
	}
}

func (e *explain) Explain(db string, query []byte) ([]byte, error) {
	var err error
	var eq proto.ExampleQuery

	err = bson.UnmarshalJSON(query, &eq)
	if err != nil {
		return nil, fmt.Errorf("explain: unable to decode query %s: %s", string(query), err)
	}

	if db == "" {
		db = eq.Db()
	}

	var result proto.BsonD
	err = e.session.DB(db).Run(eq.ExplainCmd(), &result)
	if err != nil {
		return nil, err
	}

	resultJson, err := bson.MarshalJSON(result)
	if err != nil {
		return nil, fmt.Errorf("explain: unable to encode explain result of %s: %s", string(query), err)
	}

	return resultJson, nil
}
