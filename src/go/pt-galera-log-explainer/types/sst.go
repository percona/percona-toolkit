package types

type SST struct {
	Method           string
	Type             string
	ResyncingNode    string
	ResyncedFromNode string
}

func (s *SST) Reset() {
	s.Method = ""
	s.Type = ""
	s.ResyncedFromNode = ""
	s.ResyncingNode = ""
}
