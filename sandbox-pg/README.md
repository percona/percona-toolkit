# PostgreSQL sandbox

The PostgreSQL test environment for the Percona Toolkit Go tools.

`test-env start` deploys one primary and one physical standby, both PostgreSQL
18, each holding two databases: `pagila` (the PostgreSQL port of Sakila) and
`pt_test`. No Docker and no root are involved — these are native PostgreSQL
processes under `/tmp`.

[pgs]: https://github.com/guriandoro/postgresql_sandbox
[rel]: https://github.com/guriandoro/postgresql_sandbox/releases/latest

## Prerequisites

- PostgreSQL 18 binaries.
- Go 1.27 or newer, to build and run the tests. If your distribution ships an
  older Go, set `GOTOOLCHAIN=auto` and `go` downloads the required version.
- [`pg_sandbox`][pgs] v1.0.1 or newer, on `PATH` or pointed at by
  `PG_SANDBOX_BIN`. Either take a pre-built binary from the [releases
  page][rel] — `pg_sandbox-linux-amd64`, `pg_sandbox-linux-arm64`,
  `pg_sandbox-darwin-amd64` or `pg_sandbox-darwin-arm64`, each with a
  published `SHA256SUMS`:

  ```sh
  curl -L -o ~/.local/bin/pg_sandbox \
    https://github.com/guriandoro/postgresql_sandbox/releases/latest/download/pg_sandbox-linux-amd64
  chmod +x ~/.local/bin/pg_sandbox
  ```

  or build it from a checkout:

  ```sh
  git clone https://github.com/guriandoro/postgresql_sandbox
  cd postgresql_sandbox && make build
  export PG_SANDBOX_BIN=$(pwd)/bin/pg_sandbox
  ```

## Setup

### Linux (Fedora)

Fedora's server puts the Unix socket in `/var/run/postgresql`, which only the
`postgres` user can write, so let everyone create sockets there, as in `/tmp`.

```sh
sudo dnf install -y postgresql-server postgresql golang
echo 'd /run/postgresql 1777 postgres postgres -' | sudo tee /etc/tmpfiles.d/postgresql.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/postgresql.conf
export GOTOOLCHAIN=auto
export PERCONA_TOOLKIT_BRANCH=$(pwd)
export PT_PG_SANDBOX_BASEDIR=/usr
```

### Linux (Debian/Ubuntu)

PostgreSQL 18 comes from the PGDG repository. Its server puts the Unix socket in
`/var/run/postgresql`, which only the `postgres` group can write, so join that
group and log in again before starting the sandbox.

```sh
sudo apt-get install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt-get install -y postgresql-18 golang
sudo usermod -aG postgres "$USER"
export GOTOOLCHAIN=auto
export PERCONA_TOOLKIT_BRANCH=$(pwd)
export PT_PG_SANDBOX_BASEDIR=/usr/lib/postgresql/18
```

### macOS (Homebrew)

```sh
brew install go postgresql@18
export PERCONA_TOOLKIT_BRANCH=$(pwd)
export PT_PG_SANDBOX_BASEDIR=$(brew --prefix postgresql@18)
```

### Any platform: build with `pg_sandbox`

Instead of installing packages, `pg_sandbox` can download and compile
PostgreSQL itself. This works on Linux and macOS, needs no root, and keeps
several versions side by side. It needs a C compiler, `make`, `bison`, `flex`,
Perl and the readline and zlib headers. On Fedora:

```sh
sudo dnf install -y gcc make bison flex perl readline-devel zlib-devel
export PERCONA_TOOLKIT_BRANCH=$(pwd)
export PT_PG_SANDBOX_BASEDIR=$(pg_sandbox build --bin-dir ~/pgsql 18.4)
```

## Usage

```sh
sandbox-pg/test-env checkconfig   # verify the prerequisites
make -C src/go test-pg            # build, start the sandbox, run the tests, stop it
```

`make test-pg` reuses a sandbox that is already running and leaves it running.
Otherwise it starts one and stops it afterwards, even when the tests fail.
`sandbox-pg/test-env test` does the same without building `bin/pt-pg-summary`
first.

To keep the sandbox up between runs, drive it by hand:

```sh
sandbox-pg/test-env start         # deploy primary + standby, seed the data
sandbox-pg/test-env status        # show the cluster and the discovered ports

cd src/go && make build           # TestVersionOption needs bin/pt-pg-summary
go test -v ./pt-pg-summary/... ./lib/pginfo/...

cd ../..
sandbox-pg/test-env stop          # destroy everything
```

`test-env kill` force-stops the servers if `stop` cannot finish.

Ports are allocated by `pg_sandbox`, not fixed, so `start` writes the values it
discovered to `${TMP_DIR:-/tmp}/pt-pg-sandbox/env`. The Go tests read that file,
and `test-env status` prints it. Set `PT_PG_SANDBOX_ENV` to move it.

To reach an instance by hand:

```sh
. "${TMP_DIR:-/tmp}/pt-pg-sandbox/env"
psql -h "$PG_IPV4_HOST" -p "$PG_SOURCE_PORT" -U "$PG_USERNAME" -d pagila
psql -h "$PG_IPV4_HOST" -p "$PG_REPLICA_PORT" -U "$PG_USERNAME" -d pagila
```

The tests **skip** when no sandbox is running; they do not fail. If the suite
reports skips, run `test-env start` first.

Set `PT_PG_SANDBOX_REQUIRED=1` to turn those skips into failures instead;
`make test-pg` and `test-env test` always do.

## Test data

`init.sql` creates the two databases and loads `data/pagila/`. It is applied by
`pg_sandbox cluster deploy --init-sql` against the primary before the standby
is deployed, so the data reaches the standby through `pg_basebackup`.

`init.sql` and the single `--init-sql` argument in `test-env` are the only
places that know how data gets into the sandbox. When `pg_sandbox` gains native
dataset loading, they are what gets replaced.
