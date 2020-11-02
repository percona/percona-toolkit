package pginfo

import (
	"fmt"
	"regexp"
	"time"

	"github.com/hashicorp/go-version"
	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/models"
	"github.com/pkg/errors"
	"github.com/shirou/gopsutil/process"
	"github.com/sirupsen/logrus"
)

// Process contains PostgreSQL process information
type Process struct {
	PID     int32
	CmdLine string
}

// PGInfo has exported fields containing the data collected.
// Fields are exported to be able to use them when printing the templates
type PGInfo struct {
	ClusterInfo        []*models.ClusterInfo
	ConnectedClients   []*models.ConnectedClients
	DatabaseWaitEvents []*models.DatabaseWaitEvents
	AllDatabases       []*models.Databases
	GlobalWaitEvents   []*models.GlobalWaitEvents
	PortAndDatadir     *models.PortAndDatadir
	SlaveHosts96       []*models.SlaveHosts96
	SlaveHosts10       []*models.SlaveHosts10
	Tablespaces        []*models.Tablespaces
	Settings           []*models.Setting
	Counters           map[models.Name][]*models.Counters    // Counters per database
	IndexCacheHitRatio map[string]*models.IndexCacheHitRatio // Indexes cache hit ratio per database
	TableCacheHitRatio map[string]*models.TableCacheHitRatio // Tables cache hit ratio per database
	TableAccess        map[string][]*models.TableAccess      // Table access per database
	ServerVersion      *version.Version
	Sleep              int
	Processes          []Process

	// This is the list of databases from where we should get Table Cache Hit, Index Cache Hits, etc.
	// This field is being populated on the newData function depending on the cli parameters.
	// If --databases was not specified, this array will have the list of ALL databases from the GetDatabases
	// method in the models pkg
	databases []string
	logger    *logrus.Logger
}

// New returns a new PGInfo instance with a local logger instance
func New(db models.XODB, databases []string, sleep int) (*PGInfo, error) {
	return new(db, databases, sleep, logrus.New())
}

// NewWithLogger returns a new PGInfo instance with an external logger instance
func NewWithLogger(db models.XODB, databases []string, sleep int, l *logrus.Logger) (*PGInfo, error) {
	return new(db, databases, sleep, l)
}

func new(db models.XODB, databases []string, sleep int, logger *logrus.Logger) (*PGInfo, error) {
	var err error
	info := &PGInfo{
		databases:          databases,
		Counters:           make(map[models.Name][]*models.Counters),
		TableAccess:        make(map[string][]*models.TableAccess),
		TableCacheHitRatio: make(map[string]*models.TableCacheHitRatio),
		IndexCacheHitRatio: make(map[string]*models.IndexCacheHitRatio),
		Sleep:              sleep,
		logger:             logger,
	}

	if info.AllDatabases, err = models.GetDatabases(db); err != nil {
		return nil, errors.Wrap(err, "Cannot get databases list")
	}
	info.logger.Debug("All databases list")
	for i, db := range info.AllDatabases {
		logger.Debugf("% 5d: %s", i, db.Datname)
	}

	if len(databases) < 1 {
		info.databases = make([]string, 0, len(info.AllDatabases))
		allDatabases, err := models.GetAllDatabases(db)
		if err != nil {
			return nil, errors.Wrap(err, "cannot get the list of all databases")
		}
		for _, database := range allDatabases {
			info.databases = append(info.databases, string(database.Datname))
		}
	} else {
		info.databases = make([]string, len(databases))
		copy(info.databases, databases)
	}
	info.logger.Debugf("Will collect info for these databases: %v", info.databases)

	serverVersion, err := models.GetServerVersion(db)
	if err != nil {
		return nil, errors.Wrap(err, "Cannot get server version")
	}

	if info.ServerVersion, err = parseServerVersion(serverVersion.Version); err != nil {
		return nil, fmt.Errorf("Cannot parse server version: %s", err.Error())
	}
	info.logger.Infof("Detected PostgreSQL version: %v", info.ServerVersion)

	return info, nil
}

// DatabaseNames returns the list of the database names for which information will be collected
func (i *PGInfo) DatabaseNames() []string {
	return i.databases
}

// CollectPerDatabaseInfo collects information for a specific database
func (i *PGInfo) CollectPerDatabaseInfo(db models.XODB, dbName string) (err error) {
	i.logger.Info("Collecting Table Access information")
	if i.TableAccess[dbName], err = models.GetTableAccesses(db); err != nil {
		return errors.Wrapf(err, "cannot get Table Accesses for the %s ibase", dbName)
	}

	i.logger.Info("Collecting Table Cache Hit Ratio information")
	if i.TableCacheHitRatio[dbName], err = models.GetTableCacheHitRatio(db); err != nil {
		return errors.Wrapf(err, "cannot get Table Cache Hit Ratios for the %s ibase", dbName)
	}

	i.logger.Info("Collecting Index Cache Hit Ratio information")
	if i.IndexCacheHitRatio[dbName], err = models.GetIndexCacheHitRatio(db); err != nil {
		return errors.Wrapf(err, "cannot get Index Cache Hit Ratio for the %s ibase", dbName)
	}

	return nil
}

// CollectGlobalInfo collects global information
func (i *PGInfo) CollectGlobalInfo(db models.XODB) []error {
	errs := make([]error, 0)
	var err error

	version10, _ := version.NewVersion("10.0.0")

	ch := make(chan interface{}, 2)
	i.logger.Info("Collecting global counters (1st pass)")
	getCounters(db, ch)
	c1, err := waitForCounters(ch)
	if err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get counters (1st run)"))
	} else {
		for _, counters := range c1 {
			i.Counters[counters.Datname] = append(i.Counters[counters.Datname], counters)
		}
	}

	go func() {
		i.logger.Infof("Waiting %d seconds to read  counters", i.Sleep)
		time.Sleep(time.Duration(i.Sleep) * time.Second)
		i.logger.Info("Collecting global counters (2nd pass)")
		getCounters(db, ch)
	}()

	i.logger.Info("Collecting Cluster information")
	if i.ClusterInfo, err = models.GetClusterInfos(db); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get cluster info"))
	}

	i.logger.Info("Collecting Connected Clients information")
	if i.ConnectedClients, err = models.GetConnectedClients(db); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get the connected clients list"))
	}

	i.logger.Info("Collecting Database Wait Events information")
	if i.DatabaseWaitEvents, err = models.GetDatabaseWaitEvents(db); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get databases wait events"))
	}

	i.logger.Info("Collecting Global Wait Events information")
	if i.GlobalWaitEvents, err = models.GetGlobalWaitEvents(db); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get Global Wait Events"))
	}

	i.logger.Info("Collecting Port and Data Dir information")
	if i.PortAndDatadir, err = models.GetPortAndDatadir(db); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get Port and Dir"))
	}

	i.logger.Info("Collecting Tablespaces information")
	if i.Tablespaces, err = models.GetTablespaces(db); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get Tablespaces"))
	}

	i.logger.Info("Collecting Instance Settings information")
	if i.Settings, err = models.GetSettings(db); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot get instance settings"))
	}

	if i.ServerVersion.LessThan(version10) {
		i.logger.Info("Collecting Slave Hosts (PostgreSQL < 10)")
		if i.SlaveHosts96, err = models.GetSlaveHosts96s(db); err != nil {
			errs = append(errs, errors.Wrap(err, "Cannot get slave hosts on Postgre < 10"))
		}
	}

	if i.ServerVersion.GreaterThanOrEqual(version10) {
		i.logger.Info("Collecting Slave Hosts (PostgreSQL 10+)")
		if i.SlaveHosts10, err = models.GetSlaveHosts10s(db); err != nil {
			errs = append(errs, errors.Wrap(err, "Cannot get slave hosts in Postgre 10+"))
		}
	}

	i.logger.Info("Waiting for counters information")
	c2, err := waitForCounters(ch)
	if err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot read counters (2nd run)"))
	} else {
		for _, counters := range c2 {
			i.Counters[counters.Datname] = append(i.Counters[counters.Datname], counters)
		}
		i.calcCountersDiff(i.Counters)
	}

	i.logger.Info("Collecting processes command line information")
	if err := i.collectProcesses(); err != nil {
		errs = append(errs, errors.Wrap(err, "Cannot collect processes information"))
	}

	i.logger.Info("Finished collecting global information")
	return errs
}

// SetLogger sets an external logger instance
func (i *PGInfo) SetLogger(l *logrus.Logger) {
	i.logger = l
}

// SetLogLevel changes the current log level
func (i *PGInfo) SetLogLevel(level logrus.Level) {
	i.logger.SetLevel(level)
}

func getCounters(db models.XODB, ch chan interface{}) {
	counters, err := models.GetCounters(db)
	if err != nil {
		ch <- err
	} else {
		ch <- counters
	}
}

func waitForCounters(ch chan interface{}) ([]*models.Counters, error) {
	resp := <-ch
	if err, ok := resp.(error); ok {
		return nil, err
	}

	return resp.([]*models.Counters), nil
}

func parseServerVersion(v string) (*version.Version, error) {
	re := regexp.MustCompile(`(\d?\d)(\d\d)(\d\d)`)
	m := re.FindStringSubmatch(v)
	if len(m) != 4 {
		return nil, fmt.Errorf("cannot parse version %s", v)
	}
	return version.NewVersion(fmt.Sprintf("%s.%s.%s", m[1], m[2], m[3]))
}

func (i *PGInfo) calcCountersDiff(counters map[models.Name][]*models.Counters) {
	for dbName, c := range counters {
		i.logger.Debugf("Calculating counters diff for %s database", dbName)
		diff := &models.Counters{
			Datname:      dbName,
			Numbackends:  c[1].Numbackends - c[0].Numbackends,
			XactCommit:   c[1].XactCommit - c[0].XactCommit,
			XactRollback: c[1].XactRollback - c[0].XactRollback,
			BlksRead:     c[1].BlksRead - c[0].BlksRead,
			BlksHit:      c[1].BlksHit - c[0].BlksHit,
			TupReturned:  c[1].TupReturned - c[0].TupReturned,
			TupFetched:   c[1].TupFetched - c[0].TupFetched,
			TupInserted:  c[1].TupInserted - c[0].TupInserted,
			TupUpdated:   c[1].TupUpdated - c[0].TupUpdated,
			TupDeleted:   c[1].TupDeleted - c[0].TupDeleted,
			Conflicts:    c[1].Conflicts - c[0].Conflicts,
			TempFiles:    c[1].TempFiles - c[0].TempFiles,
			TempBytes:    c[1].TempBytes - c[0].TempBytes,
			Deadlocks:    c[1].Deadlocks - c[0].Deadlocks,
		}
		counters[dbName] = append(counters[dbName], diff)
		i.logger.Debugf("Numbackends : %v - %v", c[1].Numbackends, c[0].Numbackends)
		i.logger.Debugf("XactCommit  : %v - %v", c[1].XactCommit, c[0].XactCommit)
		i.logger.Debugf("XactRollback: %v - %v", c[1].XactRollback, c[0].XactRollback)
		i.logger.Debugf("BlksRead    : %v - %v", c[1].BlksRead, c[0].BlksRead)
		i.logger.Debugf("BlksHit     : %v - %v", c[1].BlksHit, c[0].BlksHit)
		i.logger.Debugf("TupReturned : %v - %v", c[1].TupReturned, c[0].TupReturned)
		i.logger.Debugf("TupFetched  : %v - %v", c[1].TupFetched, c[0].TupFetched)
		i.logger.Debugf("TupInserted : %v - %v", c[1].TupInserted, c[0].TupInserted)
		i.logger.Debugf("TupUpdated  : %v - %v", c[1].TupUpdated, c[0].TupUpdated)
		i.logger.Debugf("TupDeleted  : %v - %v", c[1].TupDeleted, c[0].TupDeleted)
		i.logger.Debugf("Conflicts   : %v - %v", c[1].Conflicts, c[0].Conflicts)
		i.logger.Debugf("TempFiles   : %v - %v", c[1].TempFiles, c[0].TempFiles)
		i.logger.Debugf("TempBytes   : %v - %v", c[1].TempBytes, c[0].TempBytes)
		i.logger.Debugf("Deadlocks   : %v - %v", c[1].Deadlocks, c[0].Deadlocks)
		i.logger.Debugf("---")
	}
}

func (i *PGInfo) collectProcesses() error {
	procs, err := process.Processes()
	if err != nil {
		return err
	}

	i.Processes = make([]Process, 0)

	for _, proc := range procs {
		cmdLine, err := proc.Cmdline()
		if err != nil {
			continue
		}
		match, _ := regexp.MatchString("^.*?/postgres\\s.*$", cmdLine)
		if match {
			i.Processes = append(i.Processes, Process{PID: proc.Pid, CmdLine: cmdLine})
		}
	}

	return nil
}
