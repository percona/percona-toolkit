// This program is copyright 2020-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package main

import (
	"fmt"
	"log"
	"os"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/pt-k8s-debug-collector/dumper"
)

const (
	toolname = "pt-k8s-debug-collector"
)

// We do not set anything here, these variables are defined by the Makefile
var (
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint
)

type cliOptions struct {
	config.ConfigFlag
	Namespace      string `name:"namespace" help:"Namespace for collecting data. If empty data will be collected from all namespaces"`
	Resource       string `name:"resource" help:"Collect data, specific to the resource. Supported values: pxc, psmdb, pg, pgv2, ps, none, auto" default:"auto"`
	ClusterName    string `name:"cluster" help:"Cluster name"`
	Kubeconfig     string `name:"kubeconfig" help:"Path to kubeconfig"`
	ForwardPort    string `name:"forwardport" help:"Port to use for  port forwarding"`
	SkipPodSummary bool   `name:"skip-pod-summary" help:"Skip pod summary collection"`
	config.VersionCheckFlag
	config.VersionFlag
}

func (c *cliOptions) AfterApply() error {
	if c.Version {
		fmt.Println(toolname)
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)
		return nil
	}

	if c.VersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Printf("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Printf("%s", advice)
		}
	}

	if len(c.ClusterName) > 0 {
		c.Resource += "/" + c.ClusterName
	}

	return nil
}

func main() {
	opts := &cliOptions{}
	_, _, err := config.Setup(toolname, opts)
	if err != nil {
		log.Printf("cannot get parameters: %s", err.Error())
		os.Exit(1)
	}

	if opts.Version {
		return
	}

	d := dumper.New("", opts.Namespace, opts.Resource, opts.Kubeconfig, opts.ForwardPort, opts.SkipPodSummary)
	log.Println("Start collecting cluster data")

	err = d.DumpCluster()
	if err != nil {
		log.Println("Error:", err)
		os.Exit(1)
	}

	log.Println("Done")
}
