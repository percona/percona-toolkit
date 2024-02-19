package translate

import (
	"encoding/json"
	"time"
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

type subNode map[string]*WhoisNode

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
		for _, nextNode := range valueData.SubNodes {
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
