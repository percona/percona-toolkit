package templates

const BalancerStats = `
# Balancer (per day)
              Success: {{.Success}}
               Failed: {{.Failed}}
               Splits: {{.Splits}}
                Drops: {{.Drops}}
`
