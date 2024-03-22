package types

type WhoisOutput struct {
	Input     string   `json:"input"`
	IPs       []string `json:"IPs"`
	NodeNames []string `json:"nodeNames"`
	NodeUUIDs []string `json:"nodeUUIDs:"`
}
