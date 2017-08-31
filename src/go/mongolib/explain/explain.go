package explain

import (
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

func (e *explain) Explain(eq proto.ExampleQuery) ([]byte, error) {
	var result proto.BsonD
	err := e.session.DB(eq.Db()).Run(eq.ExplainCmd(), &result)
	if err != nil {
		return nil, err
	}

	resultJson, err := bson.MarshalJSON(result)
	if err != nil {
		return nil, err
	}

	return resultJson, nil
}
