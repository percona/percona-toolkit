package profiler

import (
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
)

type Stats interface {
	Reset()
	Add(doc proto.SystemProfile) error
	Queries() stats.Queries
}
