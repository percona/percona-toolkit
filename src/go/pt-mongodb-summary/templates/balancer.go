package templates

const BalancerStats = `
{{ if . -}}
# Balancer (per day)
              Success: {{.Success}}
               Failed: {{.Failed}}
               Splits: {{.Splits}}
                Drops: {{.Drops}}
{{- end -}}				
`
