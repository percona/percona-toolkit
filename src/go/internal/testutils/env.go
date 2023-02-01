package testutils

import (
	"context"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const (
	envMongoDBShard1ReplsetName    = "TEST_MONGODB_S1_RS"
	envMongoDBShard1PrimaryPort    = "TEST_MONGODB_S1_PRIMARY_PORT"
	envMongoDBShard1Secondary1Port = "TEST_MONGODB_S1_SECONDARY1_PORT"
	envMongoDBShard1Secondary2Port = "TEST_MONGODB_S1_SECONDARY2_PORT"
	//
	envMongoDBShard2ReplsetName    = "TEST_MONGODB_S2_RS"
	envMongoDBShard2PrimaryPort    = "TEST_MONGODB_S2_PRIMARY_PORT"
	envMongoDBShard2Secondary1Port = "TEST_MONGODB_S2_SECONDARY1_PORT"
	envMongoDBShard2Secondary2Port = "TEST_MONGODB_S2_SECONDARY2_PORT"
	//
	envMongoDBShard3ReplsetName    = "TEST_MONGODB_S3_RS"
	envMongoDBShard3PrimaryPort    = "TEST_MONGODB_S3_PRIMARY_PORT"
	envMongoDBShard3Secondary1Port = "TEST_MONGODB_S3_SECONDARY1_PORT"
	envMongoDBShard3Secondary2Port = "TEST_MONGODB_S3_SECONDARY2_PORT"
	//
	envMongoDBConfigsvrReplsetName = "TEST_MONGODB_CONFIGSVR_RS"
	envMongoDBConfigsvr1Port       = "TEST_MONGODB_CONFIGSVR1_PORT"
	envMongoDBConfigsvr2Port       = "TEST_MONGODB_CONFIGSVR2_PORT"
	envMongoDBConfigsvr3Port       = "TEST_MONGODB_CONFIGSVR3_PORT"
	//
	envMongoDBMongosPort = "TEST_MONGODB_MONGOS_PORT"

	envMongoDBStandalonePort = "TEST_MONGODB_STANDALONE_PORT"
	//
	envMongoDBUser     = "TEST_MONGODB_ADMIN_USERNAME"
	envMongoDBPassword = "TEST_MONGODB_ADMIN_PASSWORD"
)

var (
	// MongoDBHost is the hostname. Since it runs locally, it is localhost
	MongoDBHost = "127.0.0.1"

	// Port for standalone instance
	MongoDBStandalonePort = getEnvDefault(envMongoDBStandalonePort, "27017")

	// MongoDBShard1ReplsetName Replicaset name for shard 1
	MongoDBShard1ReplsetName = getEnvDefault(envMongoDBShard1ReplsetName, "rs1")
	// MongoDBShard1PrimaryPort is the port for the primary instance of shard 1
	MongoDBShard1PrimaryPort = getEnvDefault(envMongoDBShard1PrimaryPort, "17001")
	// MongoDBShard1Secondary1Port is the port for the secondary instance 1 of shard 1
	MongoDBShard1Secondary1Port = getEnvDefault(envMongoDBShard1Secondary1Port, "17002")
	// MongoDBShard1Secondary2Port is the port for the secondary instance 2 of shard 1
	MongoDBShard1Secondary2Port = getEnvDefault(envMongoDBShard1Secondary2Port, "17003")

	// MongoDBShard2ReplsetName Replicaset name for shard 2
	MongoDBShard2ReplsetName = getEnvDefault(envMongoDBShard2ReplsetName, "rs2")
	// MongoDBShard2PrimaryPort is the port for the primary instance of shard 2
	MongoDBShard2PrimaryPort = getEnvDefault(envMongoDBShard2PrimaryPort, "17004")
	// MongoDBShard2Secondary1Port is the port for the secondary instance 1 of shard 2
	MongoDBShard2Secondary1Port = getEnvDefault(envMongoDBShard2Secondary1Port, "17005")
	// MongoDBShard2Secondary2Port is the port for the secondary instance 1 of shard 2
	MongoDBShard2Secondary2Port = getEnvDefault(envMongoDBShard2Secondary2Port, "17006")

	// MongoDBShard3ReplsetName Replicaset name for the 3rd cluster
	MongoDBShard3ReplsetName = getEnvDefault(envMongoDBShard3ReplsetName, "rs3")
	// MongoDBShard3PrimaryPort is the port for the primary instance of 3rd cluster (non-sharded)
	MongoDBShard3PrimaryPort = getEnvDefault(envMongoDBShard3PrimaryPort, "17021")
	// MongoDBShard3Secondary1Port is the port for the secondary instance 1 on the 3rd cluster
	MongoDBShard3Secondary1Port = getEnvDefault(envMongoDBShard3Secondary1Port, "17022")
	// MongoDBShard3Secondary2Port is the port for the secondary instance 2 on the 3rd cluster
	MongoDBShard3Secondary2Port = getEnvDefault(envMongoDBShard3Secondary2Port, "17023")

	// MongoDBConfigsvrReplsetName Replicaset name for the config servers
	MongoDBConfigsvrReplsetName = getEnvDefault(envMongoDBConfigsvrReplsetName, "csReplSet")
	// MongoDBConfigsvr1Port Config server primary's port
	MongoDBConfigsvr1Port = getEnvDefault(envMongoDBConfigsvr1Port, "17007")
	// MongoDBConfigsvr2Port       = getEnvDefault(envMongoDBConfigsvr2Port)
	// MongoDBConfigsvr3Port       = getEnvDefault(envMongoDBConfigsvr3Port)

	// MongoDBMongosPort mongos port
	MongoDBMongosPort = getEnvDefault(envMongoDBMongosPort, "17000")
	// MongoDBUser username for all instances
	MongoDBUser = getEnvDefault(envMongoDBUser, "admin")
	// MongoDBPassword password for all instances
	MongoDBPassword = getEnvDefault(envMongoDBPassword, "admin123456")
	// MongoDBTimeout global connection timeout
	MongoDBTimeout = time.Duration(10) * time.Second

	// test mongodb hosts map
	hosts = map[string]map[string]string{
		MongoDBShard1ReplsetName: {
			"primary":    MongoDBHost + ":" + MongoDBShard1PrimaryPort,
			"secondary1": MongoDBHost + ":" + MongoDBShard1Secondary1Port,
			"secondary2": MongoDBHost + ":" + MongoDBShard1Secondary2Port,
		},
		MongoDBShard2ReplsetName: {
			"primary":    MongoDBHost + ":" + MongoDBShard2PrimaryPort,
			"secondary1": MongoDBHost + ":" + MongoDBShard2Secondary1Port,
			"secondary2": MongoDBHost + ":" + MongoDBShard2Secondary2Port,
		},
		MongoDBShard3ReplsetName: {
			"primary":    MongoDBHost + ":" + MongoDBShard3PrimaryPort,
			"secondary1": MongoDBHost + ":" + MongoDBShard3Secondary1Port,
			"secondary2": MongoDBHost + ":" + MongoDBShard3Secondary2Port,
		},
		MongoDBConfigsvrReplsetName: {
			"primary": MongoDBHost + ":" + MongoDBConfigsvr1Port,
		},
	}

	// The values here are just placeholders. They will be overridden by init()
	basedir string
	// MongoDBSSLDir is the directory having the SSL certs
	MongoDBSSLDir = "../docker/test/ssl"
	// MongoDBSSLPEMKeyFile PEM file used on all instances
	MongoDBSSLPEMKeyFile = filepath.Join(MongoDBSSLDir, "client.pem")
	// MongoDBSSLCACertFile CA file used on all instances
	MongoDBSSLCACertFile = filepath.Join(MongoDBSSLDir, "rootCA.crt")
)

func init() {
	MongoDBSSLDir = filepath.Join(BaseDir(), "docker/test/ssl")
	MongoDBSSLPEMKeyFile = filepath.Join(MongoDBSSLDir, "client.pem")
	MongoDBSSLCACertFile = filepath.Join(MongoDBSSLDir, "rootCA.crt")
}

func getEnvDefault(key, defVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defVal
}

// BaseDir returns the project's root dir by asking git
func BaseDir() string {
	if basedir != "" {
		return basedir
	}
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return ""
	}

	basedir = strings.TrimSpace(string(out))

	return basedir
}

// GetMongoDBAddr returns the address of an instance by replicaset name and instance type like
// (rs1, primary) or (rs1, secondary1).
func GetMongoDBAddr(rs, name string) string {
	if _, ok := hosts[rs]; !ok {
		return ""
	}

	replset := hosts[rs]

	if host, ok := replset[name]; ok {
		return host
	}

	return ""
}

// GetMongoDBReplsetAddrs return the addresses of all instances for a replicaset name.
func GetMongoDBReplsetAddrs(rs string) []string {
	addrs := []string{}

	if _, ok := hosts[rs]; !ok {
		return addrs
	}

	for _, host := range hosts[rs] {
		addrs = append(addrs, host)
	}

	return addrs
}

// TestClient returns a new MongoDB connection to the specified server port.
func TestClient(ctx context.Context, port string) (*mongo.Client, error) {
	if port == "" {
		port = MongoDBShard1PrimaryPort
	}

	hostname := "127.0.0.1"
	direct := true
	to := time.Second
	co := &options.ClientOptions{
		ConnectTimeout: &to,
		Hosts:          []string{net.JoinHostPort(hostname, port)},
		Direct:         &direct,
		Auth: &options.Credential{
			Username:    MongoDBUser,
			Password:    MongoDBPassword,
			PasswordSet: true,
		},
	}

	client, err := mongo.Connect(ctx, co)
	if err != nil {
		return nil, err
	}

	err = client.Ping(ctx, nil)
	if err != nil {
		return nil, err
	}

	return client, nil
}
