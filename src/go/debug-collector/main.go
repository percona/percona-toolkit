package main

import (
	"log"
	"os"

	"github.com/percona/percona-toolkit/src/go/debug-collector/archive"
	"github.com/percona/percona-toolkit/src/go/debug-collector/dumper"
)

func main() {
	locations := ""
	if len(os.Args) > 1 {
		locations = os.Args[1]
	}
	d := dumper.New(locations)
	log.Println("Start dump cluster")
	err := d.DumpCluster()
	if err != nil {
		log.Println(err)
		os.Exit(1)
	}

	err = archive.TarWrite(d.GetLocation(), d.Files)
	if err != nil {
		log.Println(err)
		os.Exit(1)
	}

	log.Println("Cluster dump ready")
}
