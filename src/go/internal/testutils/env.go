package testutils

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
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
	//
	envMongoDBUser     = "TEST_MONGODB_ADMIN_USERNAME"
	envMongoDBPassword = "TEST_MONGODB_ADMIN_PASSWORD"
)

var (
	MongoDBHost = "127.0.0.1"
	//
	MongoDBShard1ReplsetName    = os.Getenv(envMongoDBShard1ReplsetName)
	MongoDBShard1PrimaryPort    = os.Getenv(envMongoDBShard1PrimaryPort)
	MongoDBShard1Secondary1Port = os.Getenv(envMongoDBShard1Secondary1Port)
	MongoDBShard1Secondary2Port = os.Getenv(envMongoDBShard1Secondary2Port)
	//
	MongoDBShard2ReplsetName    = os.Getenv(envMongoDBShard2ReplsetName)
	MongoDBShard2PrimaryPort    = os.Getenv(envMongoDBShard2PrimaryPort)
	MongoDBShard2Secondary1Port = os.Getenv(envMongoDBShard2Secondary1Port)
	MongoDBShard2Secondary2Port = os.Getenv(envMongoDBShard2Secondary2Port)
	//
	MongoDBShard3ReplsetName    = os.Getenv(envMongoDBShard3ReplsetName)
	MongoDBShard3PrimaryPort    = os.Getenv(envMongoDBShard3PrimaryPort)
	MongoDBShard3Secondary1Port = os.Getenv(envMongoDBShard3Secondary1Port)
	MongoDBShard3Secondary2Port = os.Getenv(envMongoDBShard3Secondary2Port)
	//
	MongoDBConfigsvrReplsetName = os.Getenv(envMongoDBConfigsvrReplsetName)
	MongoDBConfigsvr1Port       = os.Getenv(envMongoDBConfigsvr1Port)
	MongoDBConfigsvr2Port       = os.Getenv(envMongoDBConfigsvr2Port)
	MongoDBConfigsvr3Port       = os.Getenv(envMongoDBConfigsvr3Port)
	//
	MongoDBMongosPort = os.Getenv(envMongoDBMongosPort)
	MongoDBUser       = os.Getenv(envMongoDBUser)
	MongoDBPassword   = os.Getenv(envMongoDBPassword)
	MongoDBTimeout    = time.Duration(10) * time.Second

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
	basedir              string
	MongoDBSSLDir        = "../docker/test/ssl"
	MongoDBSSLPEMKeyFile = filepath.Join(MongoDBSSLDir, "client.pem")
	MongoDBSSLCACertFile = filepath.Join(MongoDBSSLDir, "rootCA.crt")
)

func init() {
	MongoDBSSLDir = filepath.Join(BaseDir(), "docker/test/ssl")
	MongoDBSSLPEMKeyFile = filepath.Join(MongoDBSSLDir, "client.pem")
	MongoDBSSLCACertFile = filepath.Join(MongoDBSSLDir, "rootCA.crt")
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
