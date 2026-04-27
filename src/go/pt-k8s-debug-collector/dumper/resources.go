package dumper

import (
	"fmt"
	"regexp"
	"slices"
	"strings"

	log "github.com/sirupsen/logrus"
)

var resourcesRe = regexp.MustCompile(`(\w+\.(\w+).percona\.com)`)

func (d *Dumper) addPg1() error {
	dirpaths := map[string][]string{
		"pg_log": {"$PGBACKREST_DB_PATH/pg_log"},
	}

	d.individualFiles = append(d.individualFiles, individualFile{
		resourceName:  "pgo",
		containerName: "database",
		dirpaths:      dirpaths,
	})
	return nil
}

func (d *Dumper) addPg2() error {
	dirpaths := map[string][]string{
		"pg_log": {"$PGDATA/log"},
	}

	d.individualFiles = append(d.individualFiles, individualFile{
		resourceName:  "pgv2",
		containerName: "database",
		dirpaths:      dirpaths,
	})
	return nil
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
		resourceName:  "pxc",
		containerName: "logs",
		filepaths:     filepaths,
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
	}
	return s
}
