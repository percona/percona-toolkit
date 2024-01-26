package types

const (
	OperatorLogPrefix = `{"log":"`
)

type OperatorMetadata struct {
	PodName    string
	Deployment string
	Namespace  string
}
