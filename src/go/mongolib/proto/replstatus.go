package proto

const (
	REPLICA_SET_MEMBER_STARTUP = iota
	REPLICA_SET_MEMBER_PRIMARY
	REPLICA_SET_MEMBER_SECONDARY
	REPLICA_SET_MEMBER_RECOVERING
	REPLICA_SET_MEMBER_STARTUP2
	REPLICA_SET_MEMBER_UNKNOWN
	REPLICA_SET_MEMBER_ARBITER
	REPLICA_SET_MEMBER_DOWN
	REPLICA_SET_MEMBER_ROOLBACK
	REPLICA_SET_MEMBER_REMOVED
)

type Optime struct {
	Ts float64 `bson:"ts"` // The Timestamp of the last operation applied to this member of the replica set from the oplog.
	T  float64 `bson:"t"`  // The term in which the last applied operation was originally generated on the primary.
}

type Members struct {
	Optime        *Optime `bson:"optime"`        // See Optime struct
	OptimeDate    string  `bson:"optimeDate"`    // The last entry from the oplog that this member applied.
	InfoMessage   string  `bson:"infoMessage"`   // A message
	ID            int64   `bson:"_id"`           // Server ID
	Name          string  `bson:"name"`          // server name
	Health        float64 `bson:"health"`        // This field conveys if the member is up (i.e. 1) or down (i.e. 0).
	StateStr      string  `bson:"stateStr"`      // A string that describes state.
	Uptime        float64 `bson:"uptime"`        // number of seconds that this member has been online.
	ConfigVersion float64 `bson:"configVersion"` // revision # of the replica set configuration object from previous iterations of the configuration.
	Self          bool    `bson:"self"`          // true if this is the server we are currently connected
	State         float64 `bson:"state"`         // integer between 0 and 10 that represents the replica state of the member.
	ElectionTime  int64   `bson:"electionTime"`  // For the current primary, information regarding the election Timestamp from the operation log.
	ElectionDate  string  `bson:"electionDate"`  // For the current primary, an ISODate formatted date string that reflects the election date
	Set           string  `bson:"-"`
	StorageEngine StorageEngine
}

// Struct for replSetGetStatus
type ReplicaSetStatus struct {
	Date                    string    `bson:"date"`                    // Current date
	MyState                 float64   `bson:"myState"`                 // Integer between 0 and 10 that represents the replica state of the current member
	Term                    float64   `bson:"term"`                    // The election count for the replica set, as known to this replica set member. Mongo 3.2+
	HeartbeatIntervalMillis float64   `bson:"heartbeatIntervalMillis"` // The frequency in milliseconds of the heartbeats. 3.2+
	Members                 []Members `bson:"members"`                 //
	Ok                      float64   `bson:"ok"`                      //
	Set                     string    `bson:"set"`                     // Replica set name
}
