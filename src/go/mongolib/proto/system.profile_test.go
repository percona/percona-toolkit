package proto_test

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson"
)

func TestExplainCmd(t *testing.T) {
	tests := []struct {
		inDoc []byte
		want  []byte
	}{
		{
			inDoc: []byte(`{"ns":"sbtest.orders","op":"command","command":{"aggregate":"orders",` +
				`"pipeline":[{"$match":{"status":"A"}},{"$group":{"_id":"$cust_id","total":{"$sum":"$amount"}}},` +
				`{"$sort":{"total":-1}}],"cursor":{},"$db":"sbtest"}}`),
			want: []byte(`{"explain":{"aggregate":"orders","pipeline":[{"$match":{"status":"A"}},` +
				`{"$group":{"_id":"$cust_id","total":{"$sum":"$amount"}}},` +
				`{"$sort":{"total":-1}}],"cursor":{},"$db":"sbtest"}}`),
		},
		{
			inDoc: []byte(`{"ns":"sbtest.people","op":"command","command":` +
				`{"count":"people","query":{},"fields":{},"$db":"sbtest"}}`),
			want: []byte(`{"explain":{"count":"people","query":{},"fields":{}}}`),
		},
	}

	for _, tc := range tests {
		var want bson.D
		err := bson.UnmarshalExtJSON(tc.want, false, &want)
		assert.NoError(t, err)

		var doc proto.SystemProfile
		err = bson.UnmarshalExtJSON(tc.inDoc, false, &doc)
		assert.NoError(t, err)

		eq := proto.NewExampleQuery(doc)

		assert.Equal(t, want, eq.ExplainCmd())
	}
}
