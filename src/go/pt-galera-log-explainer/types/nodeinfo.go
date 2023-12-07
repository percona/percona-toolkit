package types

// NodeInfo is mainly used by "whois" subcommand
// This is to display its result
// As it's the base work for "sed" subcommand, it's in types package
type NodeInfo struct {
	Input     string   `json:"input"`
	IPs       []string `json:"IPs"`
	NodeNames []string `json:"nodeNames"`
	Hostname  string   `json:"hostname"`
	NodeUUIDs []string `json:"nodeUUIDs:"`
}
