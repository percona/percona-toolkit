package main

/*
type whois struct {
	Search string   `arg:"" name:"search" help:"the identifier (node name, ip, uuid, hash) to search"`
	Paths  []string `arg:"" name:"paths" help:"paths of the log to use"`
}

func (w *whois) Help() string {
	return `Take any type of info pasted from error logs and find out about it.
It will list known node name(s), IP(s), hostname(s), and other known node's UUIDs.
`
}

func (w *whois) Run() error {

	toCheck := regex.AllRegexes()
	timeline, err := timelineFromPaths(CLI.Whois.Paths, toCheck)
	if err != nil {
		return errors.Wrap(err, "found nothing to translate")
	}
	ctxs := timeline.GetLatestContextsByNodes()

	ni := whoIs(ctxs, CLI.Whois.Search)

	json, err := json.MarshalIndent(ni, "", "\t")
	if err != nil {
		return err
	}
	fmt.Println(string(json))
	return nil
}

func whoIs(ctxs map[string]types.LogCtx, search string) types.NodeInfo {
		ni := types.NodeInfo{Input: search}
		if regex.IsNodeUUID(search) {
			search = utils.UUIDToShortUUID(search)
		}
		var (
			ips       []string
			hashes    []string
			nodenames []string
		)
			for _, ctx := range ctxs {
				if utils.SliceContains(ctx.OwnNames, search) || utils.SliceContains(ctx.OwnHashes, search) || utils.SliceContains(ctx.OwnIPs, search) {
					ni.NodeNames = ctx.OwnNames
					ni.NodeUUIDs = ctx.OwnHashes
					ni.IPs = ctx.OwnIPs
					ni.Hostname = ctx.OwnHostname()
				}

				if nodename, ok := ctx.HashToNodeName[search]; ok {
					nodenames = utils.SliceMergeDeduplicate(nodenames, []string{nodename})
					hashes = utils.SliceMergeDeduplicate(hashes, []string{search})
				}

				if ip, ok := ctx.HashToIP[search]; ok {
					ips = utils.SliceMergeDeduplicate(ips, []string{ip})
					hashes = utils.SliceMergeDeduplicate(hashes, []string{search})

				} else if nodename, ok := ctx.IPToNodeName[search]; ok {
					nodenames = utils.SliceMergeDeduplicate(nodenames, []string{nodename})
					ips = utils.SliceMergeDeduplicate(ips, []string{search})

				} else if utils.SliceContains(ctx.AllNodeNames(), search) {
					nodenames = utils.SliceMergeDeduplicate(nodenames, []string{search})
				}

				for _, nodename := range nodenames {
					hashes = utils.SliceMergeDeduplicate(hashes, ctx.HashesFromNodeName(nodename))
					ips = utils.SliceMergeDeduplicate(ips, ctx.IPsFromNodeName(nodename))
				}

				for _, ip := range ips {
					hashes = utils.SliceMergeDeduplicate(hashes, ctx.HashesFromIP(ip))
					nodename, ok := ctx.IPToNodeName[ip]
					if ok {
						nodenames = utils.SliceMergeDeduplicate(nodenames, []string{nodename})
					}
				}
				for _, hash := range hashes {
					nodename, ok := ctx.HashToNodeName[hash]
					if ok {
						nodenames = utils.SliceMergeDeduplicate(nodenames, []string{nodename})
					}
				}
			}
			ni.NodeNames = nodenames
			ni.NodeUUIDs = hashes
			ni.IPs = ips
			return ni
	return types.NodeInfo{}
}
*/
