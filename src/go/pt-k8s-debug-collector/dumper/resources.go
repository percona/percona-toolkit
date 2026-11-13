package dumper

import (
	"context"
	"fmt"
	"path"
	"regexp"
	"slices"
	"strings"
	"time"

	log "github.com/sirupsen/logrus"
	corev1 "k8s.io/api/core/v1"
)

var resourcesRe = regexp.MustCompile(`(\w+\.([\w-]+)\.(percona|crunchydata)\.com)`)

const (
	pgLogDirectoryVar     = "PG_LOG_DIRECTORY"
	pgLogDirectoryTimeout = 30 * time.Second
)

func (d *Dumper) addPg1() error {
	dirpaths := map[string][]string{
		"pg_log": {"$PGBACKREST_DB_PATH/pg_log"},
	}

	d.individualFiles = append(d.individualFiles, individualFile{
		resourceName:   "pgo",
		containerNames: []string{"database"},
		dirpaths:       dirpaths,
	})
	return nil
}

func (d *Dumper) addPg2() error {
	d.individualFiles = append(d.individualFiles, d.pg2IndividualFile("pgv2"))
	return nil
}

func (d *Dumper) addCrunchy() error {
	d.individualFiles = append(d.individualFiles, d.pg2IndividualFile("crunchy"))
	return nil
}

func (d *Dumper) pgLogDirectory(ctx context.Context, pod corev1.Pod, container string, env map[string]string) string {
	pgdata := env["PGDATA"]

	ctx, cancel := context.WithTimeout(ctx, pgLogDirectoryTimeout)
	defer cancel()

	out, stderr, err := d.executeInPod(ctx, []string{"psql", "-XAtc", "SHOW log_directory"}, pod, container, nil)
	if err != nil {
		fallback := resolvePgLogDirectory("", pgdata)
		log.Warnf("Failed to get log_directory in pod %s/%s, using %q: %v (stderr: %s)", pod.Namespace, pod.Name, fallback, err, stderr.String())
		return fallback
	}

	return resolvePgLogDirectory(out.String(), pgdata)
}

func resolvePgLogDirectory(out, pgdata string) string {
	dir := strings.TrimSpace(out)
	switch {
	case dir == "":
		return path.Join(pgdata, "log")
	case path.IsAbs(dir):
		return dir
	default:
		return path.Join(pgdata, dir)
	}
}

func (d *Dumper) pg2IndividualFile(resourceName string) individualFile {
	dirpaths := map[string][]string{
		"pg_log":         {"$" + pgLogDirectoryVar},
		"pgbackrest_log": {"pgdata/pgbackrest/log"},
	}

	tools := map[string][]toolLog{
		"": {
			{
				filename: "patronictl-list.log",
				args:     []string{"patronictl", "list"},
			},
			{
				filename: "pgbackrest-info.log",
				args:     []string{"pgbackrest", "info"},
			},
		},
	}

	return individualFile{
		resourceName:   resourceName,
		containerNames: []string{"database"},
		dirpaths:       dirpaths,
		toolCmds:       tools,
		dynamicEnv:     map[string]dynamicEnvFunc{pgLogDirectoryVar: d.pgLogDirectory},
	}
}

func (d *Dumper) addPxc() error {
	filepaths := []string{
		"var/lib/mysql/mysqld-error.log",
		"var/lib/mysql/innobackup.backup.log",
		"var/lib/mysql/innobackup.move.log",
		"var/lib/mysql/innobackup.prepare.log",
		"var/lib/mysql/grastate.dat",
		"var/lib/mysql/gvwstate.dat",
		"var/lib/mysql/mysqld.post.processing.log",
		"var/lib/mysql/auto.cnf",
	}

	d.individualFiles = append(d.individualFiles, individualFile{
		resourceName:   "pxc",
		containerNames: []string{"logs", "pxc"},
		filepaths:      filepaths,
	})
	return nil
}

func (d *Dumper) addPs() error {
	return nil
}

func (d *Dumper) addPsmdb() error {
	return nil
}

// TODO: review and make simple
func (d *Dumper) autoCustomResource() ([]string, error) {
	apiGroupList, err := d.clientSet.DiscoveryClient.ServerGroups()
	if err != nil {
		return nil, fmt.Errorf("error getting server groups: %w", err)
	}
	var resourceNames string
	var beforeSorting []string
	uniqueResourceNames := make(map[string]bool)
	for _, group := range apiGroupList.Groups {
		for _, version := range group.Versions {
			resourceList, err := d.clientSet.DiscoveryClient.ServerResourcesForGroupVersion(version.GroupVersion)
			if err != nil {
				log.Warnf("could not get resources for GroupVersion %s: %v", version.GroupVersion, err)
				continue
			}
			for _, resource := range resourceList.APIResources {
				if resource.Name != "" && !strings.Contains(resource.Name, "/") {
					if group.Name != "" {
						uniqueResourceNames[resource.Name+"."+group.Name] = true
					} else {
						uniqueResourceNames[resource.Name] = true
					}
				}
			}
		}
	}
	for name := range uniqueResourceNames {
		beforeSorting = append(beforeSorting, name)
	}
	slices.Sort(beforeSorting)
	for _, name := range beforeSorting {
		resourceNames = resourceNames + name + "\n"
	}

	matches := resourcesRe.FindAllStringSubmatch(resourceNames, -1)
	if len(matches) == 0 {
		return []string{"none"}, nil
	}

	uniqueResources := make(map[string]bool, 0)
	for _, match := range matches {
		uniqueResources[match[2]] = true
	}

	result := make([]string, 0)
	for res := range uniqueResources {
		result = append(result, res)
	}

	return result, nil
}

func parseResourceSpec(resource string) (string, string) {
	resource = strings.TrimSpace(resource)
	if resource == "" {
		return "", ""
	}

	resourceName, clusterName, found := strings.Cut(resource, "/")
	if !found {
		return resourceName, ""
	}

	return resourceName, clusterName
}

// TODO: rewrite to use map or switch
func resourceType(s string) string {
	if s == "auto" {
		return "auto"
	} else if s == "pxc" || strings.HasPrefix(s, "pxc/") {
		return "pxc"
	} else if s == "psmdb" || strings.HasPrefix(s, "psmdb/") {
		return "psmdb"
	} else if s == "pg" || strings.HasPrefix(s, "pg/") {
		return "pg"
	} else if s == "pgo" || strings.HasPrefix(s, "pgo/") {
		return "pg"
	} else if s == "pgv2" || strings.HasPrefix(s, "pgv2/") {
		return "pgv2"
	} else if s == "ps" || strings.HasPrefix(s, "ps/") {
		return "ps"
	} else if s == "postgres-operator" {
		return "crunchy"
	}
	return s
}
