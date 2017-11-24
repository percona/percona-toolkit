package filter

import (
	"strings"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

type Filter func(proto.SystemProfile) bool

// This func receives a doc from the profiler and returns:
// true : the document must be considered
// false: the document must be skipped
func NewFilterByCollection(collectionsToSkip []string) func(proto.SystemProfile) bool {
	return func(doc proto.SystemProfile) bool {
		for _, collection := range collectionsToSkip {
			if strings.HasSuffix(doc.Ns, collection) {
				return false
			}
		}
		return true
	}
}
