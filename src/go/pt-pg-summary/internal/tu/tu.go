package tu // test utils

import (
	"log"
	"os"
	"os/exec"
	"strings"
)

const (
	ipv4Host = "127.0.0.1"
	ipv6Host = "::1"
	username = "postgres"
	password = "root"

	ipv4PG9Port  = "6432"
	ipv4PG10Port = "6433"
	ipv4PG11Port = "6434"
	ipv4PG12Port = "6435"

	ipv6PG9Port  = "6432"
	ipv6PG10Port = "6432"
	ipv6PG11Port = "6432"
	ipv6PG12Port = "6432"

	pg9Container  = "go_postgres9_1"
	pg10Container = "go_postgres10_1"
	pg11Container = "go_postgres11_1"
	pg12Container = "go_postgres12_1"
)

var (
	// IPv4Host env(PG_IPV4_HOST) or 127.0.0.1
	IPv4Host = getVar("PG_IPV4_HOST", ipv4Host)
	// IPv6Host env(PG_IPV6_HOST) or ::1
	IPv6Host = getVar("PG_IPV6_HOST", ipv6Host)
	// Password env(PG_PASSWORD) or root
	Password = getVar("PG_PASSWORD", password)
	// Username env(PG_USERNAME) or PG
	Username = getVar("PG_USERNAME", username)

	IPv4PG9Port  = getVar("PG_IPV4_9_PORT", ipv4PG9Port)
	IPv4PG10Port = getVar("PG_IPV4_10_PORT", ipv4PG10Port)
	IPv4PG11Port = getVar("PG_IPV4_11_PORT", ipv4PG11Port)
	IPv4PG12Port = getVar("PG_IPV4_12_PORT", ipv4PG12Port)

	IPv6PG9Port  = getVar("PG_IPV6_9_PORT", ipv6PG9Port)
	IPv6PG10Port = getVar("PG_IPV6_10_PORT", ipv6PG10Port)
	IPv6PG11Port = getVar("PG_IPV6_11_PORT", ipv6PG11Port)
	IPv6PG12Port = getVar("PG_IPV6_12_PORT", ipv6PG12Port)

	PG9DockerIP  = getContainerIP(pg9Container)
	PG10DockerIP = getContainerIP(pg10Container)
	PG11DockerIP = getContainerIP(pg11Container)
	PG12DockerIP = getContainerIP(pg12Container)

	DefaultPGPort = "5432"
)

func getVar(varname, defaultValue string) string {
	if v := os.Getenv(varname); v != "" {
		return v
	}
	return defaultValue
}

func getContainerIP(container string) string {
	cmd := []string{"docker", "inspect", "-f", "'{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'", container}
	out, err := exec.Command(cmd[0], cmd[1:]...).Output()
	if err != nil {
		log.Fatalf("error getting IP address of %q container: %s", container, err)
	}

	ip := strings.TrimSpace(string(out))
	if ip == "" {
		log.Fatalf("error getting IP address of %q container (empty)", container)
	}
	return ip
}
