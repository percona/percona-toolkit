package stats

import (
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

type Fingerprinter interface {
	Fingerprint(doc proto.SystemProfile) (fingerprinter.Fingerprint, error)
}
