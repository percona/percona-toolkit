package translate

import (
	"encoding/json"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/xlab/treeprint"
	"golang.org/x/exp/slices"
)

type WhoisNode struct {
	parentNode *WhoisNode            `json:"-"`
	rootNode   *WhoisNode            `json:"-"`
	nodetype   string                `json:"-"`
	Values     map[string]WhoisValue // the key here are the actual values stored for this node
}

type WhoisValue struct {
	Timestamp *time.Time            `json:",omitempty"` // only the base one will be nil
	SubNodes  map[string]*WhoisNode `json:",omitempty"` // associating the next node to a type of value (uuid, ip, node name)
}

// When initiating recursion, instead of iterating over maps we should iterate over a fixed order of types
// maps orders are not guaranteed, and there are multiple paths of identifying information
// Forcing the order ultimately helps to provide repeatable output, so it helps with regression tests
// It also helps reducing graph depth, as "nodename" will have most of its information linked to it directly
var forcedIterationOrder = []string{"nodename", "ip", "uuid"}

func Whois(search, searchtype string) *WhoisNode {
	w := &WhoisNode{
		nodetype: searchtype,
		Values:   map[string]WhoisValue{},
	}
	w.rootNode = w
	w.Values[search] = WhoisValue{SubNodes: map[string]*WhoisNode{}}
	w.filter()
	return w
}

func (v WhoisValue) AddChildKey(parentNode *WhoisNode, nodetype, value string, timestamp time.Time) {
	child := v.SubNodes[nodetype]
	nodeNew := false
	if child == nil {
		child = &WhoisNode{
			nodetype:   nodetype,
			rootNode:   parentNode.rootNode,
			parentNode: parentNode,
			Values:     map[string]WhoisValue{},
		}
		// delaying storage, we have to make sure
		// not to store duplicate nodes first to avoid infinite recursion
		nodeNew = true
	}
	ok := child.addKey(value, timestamp)
	if nodeNew && ok {
		v.SubNodes[nodetype] = child
	}
}

func (n *WhoisNode) MarshalJSON() ([]byte, error) {
	return json.Marshal(n.Values)
}

func (n *WhoisNode) String() string {
	return n.tree().String()
}

func (n *WhoisNode) tree() treeprint.Tree {
	root := treeprint.NewWithRoot(utils.Paint(utils.GreenText, n.nodetype) + ":")
	for _, value := range n.valuesSortedByTimestamps() {
		valueData := n.Values[value]
		str := value
		if valueData.Timestamp != nil {
			str += utils.Paint(utils.BlueText, " ("+valueData.Timestamp.String()+")")
		}
		if len(valueData.SubNodes) == 0 {
			root.AddNode(str)
			continue
		}
		subtree := root.AddBranch(str)

		// forcing map iteration for repeatable outputs
		for _, subNodeType := range forcedIterationOrder {
			subnode, ok := valueData.SubNodes[subNodeType]
			if ok {
				subtree.AddNode(subnode.tree())
			}
		}
	}
	return root
}

func (n *WhoisNode) valuesSortedByTimestamps() []string {
	values := []string{}
	for value := range n.Values {
		values = append(values, value)
	}

	// keep nil timestamps at the top
	slices.SortFunc(values, func(a, b string) bool {
		if n.Values[a].Timestamp == nil && n.Values[b].Timestamp == nil {
			return a < b
		}
		if n.Values[a].Timestamp == nil { // implied b!=nil
			return true // meaning, nil < nonnil, a < b
		}
		if n.Values[b].Timestamp == nil { // implied a!=nil
			return false // meaning a is greater than b
		}
		return n.Values[a].Timestamp.Before(*n.Values[b].Timestamp)
	})
	return values
}

func (n *WhoisNode) addKey(value string, timestamp time.Time) bool {
	storedValue := n.rootNode.GetValueData(value, n.nodetype)
	if storedValue != nil {
		if storedValue.Timestamp != nil && storedValue.Timestamp.Before(timestamp) {
			storedValue.Timestamp = &timestamp
		}
		return false
	}
	n.Values[value] = WhoisValue{Timestamp: &timestamp, SubNodes: map[string]*WhoisNode{}}
	return true
}

func (n *WhoisNode) GetValueData(search, searchType string) *WhoisValue {
	for value, valueData := range n.Values {
		if n.nodetype == searchType && search == value {
			return &valueData
		}
		// iterating over subnodes here is fine, as the value we search for should be unique
		// so the way to access don't have to be forced
		for _, nextNode := range valueData.SubNodes {
			if nextNode != nil {
				if valueData := nextNode.GetValueData(search, searchType); valueData != nil {
					return valueData
				}
			}
		}
	}
	return nil
}

func (n *WhoisNode) filter() {
	switch n.nodetype {
	case "ip":
		n.filterDBUsingIP()
	case "uuid":
		n.FilterDBUsingUUID()
	case "nodename":
		n.FilterDBUsingNodeName()
	}

	for _, valueData := range n.Values {
		// see comment on "forcedIterationOrder"
		for _, nextNodeType := range forcedIterationOrder {
			nextNode := valueData.SubNodes[nextNodeType]
			if nextNode != nil {
				nextNode.filter()
			}
		}
	}
}

func (n *WhoisNode) filterDBUsingIP() {
	for ip, valueData := range n.Values {
		for hash, ip2 := range db.HashToIP {
			if ip == ip2.Value {
				valueData.AddChildKey(n, "uuid", hash, ip2.Timestamp)
			}
		}
		nodenames, ok := db.IPToNodeNames[ip]
		if ok {
			for _, nodename := range nodenames {
				valueData.AddChildKey(n, "nodename", nodename.Value, nodename.Timestamp)
			}
		}
	}

	return
}

func (n *WhoisNode) FilterDBUsingUUID() {
	for uuid, valueData := range n.Values {
		nodenames, ok := db.HashToNodeNames[uuid]
		if ok {
			for _, nodename := range nodenames {
				valueData.AddChildKey(n, "nodename", nodename.Value, nodename.Timestamp)
			}
		}
		ip, ok := db.HashToIP[uuid]
		if ok {
			valueData.AddChildKey(n, "ip", ip.Value, ip.Timestamp)
		}
	}

	return
}

func (n *WhoisNode) FilterDBUsingNodeName() {
	for nodename, valueData := range n.Values {
		// unspecified will sometimes appears in some failures
		// using it will lead to non-sense data as it can bridge the rest of the whole graph
		if nodename == "unspecified" {
			continue
		}
		for uuid, nodenames2 := range db.HashToNodeNames {
			for _, nodename2 := range nodenames2 {
				if nodename == nodename2.Value {
					valueData.AddChildKey(n, "uuid", uuid, nodename2.Timestamp)
				}
			}
		}
		for ip, nodenames2 := range db.IPToNodeNames {
			for _, nodename2 := range nodenames2 {
				if nodename == nodename2.Value {
					valueData.AddChildKey(n, "ip", ip, nodename2.Timestamp)
				}
			}
		}
	}

	return
}
