package proto

import "time"

type SystemProfile struct {
	AllUsers        []interface{} `bson:"allUsers"`
	Client          string        `bson:"client"`
	CursorExhausted bool          `bson:"cursorExhausted"`
	DocsExamined    int           `bson:"docsExamined"`
	ExecStats       struct {
		Advanced                    int `bson:"advanced"`
		ExecutionTimeMillisEstimate int `bson:"executionTimeMillisEstimate"`
		InputStage                  struct {
			Advanced                    int    `bson:"advanced"`
			Direction                   string `bson:"direction"`
			DocsExamined                int    `bson:"docsExamined"`
			ExecutionTimeMillisEstimate int    `bson:"executionTimeMillisEstimate"`
			Filter                      struct {
				Date struct {
					Eq string `bson:"$eq"`
				} `bson:"date"`
			} `bson:"filter"`
			Invalidates  int    `bson:"invalidates"`
			IsEOF        int    `bson:"isEOF"`
			NReturned    int    `bson:"nReturned"`
			NeedTime     int    `bson:"needTime"`
			NeedYield    int    `bson:"needYield"`
			RestoreState int    `bson:"restoreState"`
			SaveState    int    `bson:"saveState"`
			Stage        string `bson:"stage"`
			Works        int    `bson:"works"`
		} `bson:"inputStage"`
		Invalidates  int    `bson:"invalidates"`
		IsEOF        int    `bson:"isEOF"`
		LimitAmount  int    `bson:"limitAmount"`
		NReturned    int    `bson:"nReturned"`
		NeedTime     int    `bson:"needTime"`
		NeedYield    int    `bson:"needYield"`
		RestoreState int    `bson:"restoreState"`
		SaveState    int    `bson:"saveState"`
		Stage        string `bson:"stage"`
		Works        int    `bson:"works"`
	} `bson:"execStats"`
	KeyUpdates   int `bson:"keyUpdates"`
	KeysExamined int `bson:"keysExamined"`
	Locks        struct {
		Collection struct {
			AcquireCount struct {
				R int `bson:"R"`
			} `bson:"acquireCount"`
		} `bson:"Collection"`
		Database struct {
			AcquireCount struct {
				R int `bson:"r"`
			} `bson:"acquireCount"`
		} `bson:"Database"`
		Global struct {
			AcquireCount struct {
				R int `bson:"r"`
			} `bson:"acquireCount"`
		} `bson:"Global"`
		MMAPV1Journal struct {
			AcquireCount struct {
				R int `bson:"r"`
			} `bson:"acquireCount"`
		} `bson:"MMAPV1Journal"`
	} `bson:"locks"`
	Millis         int                    `bson:"millis"`
	Nreturned      int                    `bson:"nreturned"`
	Ns             string                 `bson:"ns"`
	NumYield       int                    `bson:"numYield"`
	Op             string                 `bson:"op"`
	Protocol       string                 `bson:"protocol"`
	Query          map[string]interface{} `bson:"query"`
	ResponseLength int                    `bson:"responseLength"`
	Ts             time.Time              `bson:"ts"`
	User           string                 `bson:"user"`
	WriteConflicts int                    `bson:"writeConflicts"`
}
