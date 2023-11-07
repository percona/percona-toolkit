package main

/*
type sed struct {
	Paths []string `arg:"" name:"paths" help:"paths of the log to use"`
	ByIP  bool     `help:"Replace by IP instead of name"`
}

func (s *sed) Help() string {

	return fmt.Sprintf(`sed translates a log, replacing node UUID, IPS, names with either name or IP everywhere. By default it replaces by name.

Use like so:
	cat node1.log | %[1]s sed *.log | less
	%[1]s sed *.log < node1.log | less

You can also simply call the command to get a generated sed command to review and apply yourself
	%[1]s sed *.log`, toolname)
}

func (s *sed) Run() error {
	toCheck := regex.AllRegexes()
	timeline, err := timelineFromPaths(s.Paths, toCheck)
	if err != nil {
		return errors.Wrap(err, "found nothing worth replacing")
	}
	ctxs := timeline.GetLatestContextsByNodes()

	args := []string{}
	for key, ctx := range ctxs {

		tosearchs := []string{key}
		tosearchs = append(tosearchs, ctx.OwnHashes...)
		tosearchs = append(tosearchs, ctx.OwnIPs...)
		tosearchs = append(tosearchs, ctx.OwnNames...)
		for _, tosearch := range tosearchs {
			ni := whoIs(ctxs, tosearch)

			fmt.Println(ni)
			switch {
			case CLI.Sed.ByIP:
				args = append(args, sedByIP(ni)...)
			default:
				args = append(args, sedByName(ni)...)
			}
		}

	}
	if len(args) == 0 {
		return errors.New("could not find informations to replace")
	}

	fstat, err := os.Stdin.Stat()
	if err != nil {
		return err
	}
	if fstat.Size() == 0 {
		fmt.Println("No files found in stdin, returning the sed command instead:")
		fmt.Println("sed", strings.Join(args, " "))
		return nil
	}

	cmd := exec.Command("sed", args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Start()
	if err != nil {
		return err
	}
	return cmd.Wait()
}

func sedByName(ni types.NodeInfo) []string {
	if len(ni.NodeNames) == 0 {
		return nil
	}
	elem := ni.NodeNames[0]
	args := sedSliceWith(ni.NodeUUIDs, elem)
	args = append(args, sedSliceWith(ni.IPs, elem)...)
	return args
}

func sedByIP(ni types.NodeInfo) []string {
	if len(ni.IPs) == 0 {
		return nil
	}
	elem := ni.IPs[0]
	args := sedSliceWith(ni.NodeUUIDs, elem)
	args = append(args, sedSliceWith(ni.NodeNames, elem)...)
	return args
}

func sedSliceWith(elems []string, replace string) []string {
	args := []string{}
	for _, elem := range elems {
		args = append(args, "-e")
		args = append(args, "s/"+elem+"/"+replace+"/g")
	}
	return args
}
*/
