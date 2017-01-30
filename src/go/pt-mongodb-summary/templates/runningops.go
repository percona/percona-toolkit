package templates

const RunningOps = `
# Running Ops ############################################################################################

Type         Min        Max        Avg
Insert    {{printf "% 8d" .Insert.Min}}   {{printf "% 8d" .Insert.Max}}   {{printf "% 8d" .Insert.Avg}}/{{.SampleRate}}
Query     {{printf "% 8d" .Query.Min}}   {{printf "% 8d" .Query.Max}}   {{printf "% 8d" .Query.Avg}}/{{.SampleRate}}
Update    {{printf "% 8d" .Update.Min}}   {{printf "% 8d" .Update.Max}}   {{printf "% 8d" .Update.Avg}}/{{.SampleRate}}
Delete    {{printf "% 8d" .Delete.Min}}   {{printf "% 8d" .Delete.Max}}   {{printf "% 8d" .Delete.Avg}}/{{.SampleRate}}
GetMore   {{printf "% 8d" .GetMore.Min}}   {{printf "% 8d" .GetMore.Max}}   {{printf "% 8d" .GetMore.Avg}}/{{.SampleRate}}
Command   {{printf "% 8d" .Command.Min}}   {{printf "% 8d" .Command.Max}}   {{printf "% 8d" .Command.Avg}}/{{.SampleRate}}
`
