# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All make commands run from `/src/go/` (the Go module root), not the tool directory itself.

**Build:**
```bash
make build                # Build for current platform → ../../bin/pt-mongodb-summary
make linux-amd64          # Cross-compile for Linux x86-64
make darwin-arm64         # Cross-compile for macOS Apple Silicon
VERSION=3.7.1 make linux-amd64  # Build with version embedded via LDFLAGS
```

**Test:**
```bash
make test                 # Runs ./runtests.sh (requires Docker for MongoDB containers)
make env-up               # Start MongoDB test containers (standalone + sharded cluster)
make env-down             # Stop test containers
go test -v ./...          # Run tests directly (from tool directory)
go test -v -run TestName ./...  # Run a specific test
```

**Lint & Format:**
```bash
make style                # Check formatting with gofmt
make vet                  # Run go vet
make format               # Auto-format with gofumpt and gofumports
```

## Architecture

`pt-mongodb-summary` connects to a MongoDB instance (standalone, replica set, or sharded cluster), collects diagnostic data via admin commands, and renders a human-readable or JSON report.

### Data flow

```
main() → connect → collect → format → output
```

1. **Connect** (`getClientOptions`): Builds `*options.ClientOptions` from CLI flags or URI, handling TLS and auth.
2. **Collect**: Each `get*` function runs MongoDB admin commands and returns a typed struct:
   - `getHostInfo` → `hostInfo` (hostInfo, serverStatus, cmdLineOpts commands)
   - `getMongosInfo` → `mongosInfo` (queries `config.mongos` collection)
   - `getSecuritySettings` → `security` (auth/SSL from serverStatus + usersInfo + rolesInfo)
   - `getOpCountersStats` → `opCounters` (samples serverStatus N times)
   - `oplog.GetOplogInfo` → `[]proto.OplogInfo` (reads local.oplog.rs)
   - `getClusterwideInfo` → `clusterwideInfo` (listDatabases, collStats, sh.status; mongos only)
   - `GetBalancerStats` → `proto.BalancerStats` (parses config.changelog; mongos only)
3. **Aggregate** into `collectedInfo` struct.
4. **Format** (`formatResults`): Either marshal to JSON or render via Go templates in `templates/`.

### Templates

Each report section has a dedicated template file under `templates/`. Templates receive the full `collectedInfo` struct. Adding a new output section means adding a template file and calling it from `formatResults`.

### Shared packages

- `../../mongolib/proto/` — shared MongoDB data types (e.g., `Members`, `OplogInfo`, `BalancerStats`)
- `../../mongolib/util/` — MongoDB helpers (e.g., `GetReplicasetMembers`)
- `../../lib/config/` — config file loading
- `../../lib/versioncheck/` — online version check against Percona's API
- `../../internal/testutils/` — test helpers (connection setup, fixtures)

### Test fixtures

Sample MongoDB command responses live in `test/sample/*.json`. Tests in `main_test.go` unmarshal these fixtures to test parsing logic without a live MongoDB connection. Integration tests (via `runtests.sh`) require the Docker cluster from `make env-up`.

## Key conventions

- CLI parsing uses `github.com/alecthomas/kong` via `config.Setup()`. New options are added as fields with kong struct tags in `cliOptions`. Validation and side-effects (log level, version check, password prompt, positional host:port) go in `AfterApply()`. Config files (`~/.pt-mongodb-summary.conf`, `/etc/percona-toolkit/pt-mongodb-summary.conf`) are automatically supported.
- Logging is via `github.com/sirupsen/logrus`; level is set from `--log-level` flag.
- MongoDB connection URI takes precedence over individual host/port/auth flags.
- The binary embeds `Version`, `Build`, `GoVersion`, and `Commit` via LDFLAGS at build time.
