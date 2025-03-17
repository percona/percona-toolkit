# pt-stalk (Go Version)

A Go implementation of the Percona pt-stalk tool for collecting MySQL and system metrics.

## Installation

Install using go:

    go install github.com/percona/pt-stalk@latest

## Usage Examples

### Basic MySQL Monitoring

Collect only MySQL metrics:

    pt-stalk --collectors=mysql \
      --mysql-host=localhost \
      --mysql-user=root \
      --mysql-password=secret \
      --dest=/var/log/mysql/samples \
      --interval=1

### MySQL and System Monitoring

Collect both MySQL and system metrics:

    pt-stalk --collectors=mysql,system \
      --mysql-host=localhost \
      --mysql-user=root \
      --mysql-password=secret \
      --collect-gdb=true \
      --collect-tcpdump=true \
      --dest=/var/log/mysql/samples \
      --interval=1

### Running as a Daemon

Run pt-stalk in the background:

    pt-stalk --collectors=mysql,system \
      --mysql-host=localhost \
      --mysql-user=root \
      --mysql-password=secret \
      --daemonize=true \
      --pid=/var/run/pt-stalk.pid \
      --log=/var/log/pt-stalk.log \
      --dest=/var/log/mysql/samples

### Using a Custom Plugin

Run with a custom plugin script:

    pt-stalk --collectors=mysql \
      --mysql-host=localhost \
      --mysql-user=root \
      --mysql-password=secret \
      --plugin=/path/to/custom/plugin.sh \
      --dest=/var/log/mysql/samples

Example plugin script (plugin.sh):

    #!/bin/bash
    # Environment variables available:
    # PT_DEST - destination directory
    # PT_PREFIX - file prefix
    # PT_INTERVAL - check interval
    # PT_RUNTIME - collection duration

    echo "Custom collection started" > "$PT_DEST/${PT_PREFIX}_custom.txt"
    # Add your custom collection logic here

### Basic MongoDB Monitoring

Collect MongoDB metrics:

    pt-stalk --collectors=mongodb \
      --mongodb-host=localhost \
      --mongodb-user=myuser \
      --mongodb-password=secret \
      --dest=/var/log/mongodb/samples \
      --interval=1

## Configuration Options

### Common Options
- --collectors: Comma-separated list of collectors to enable (mysql,system)
- --interval: Check interval in seconds (default: 1)
- --run-time: How long to collect data in seconds (default: 30)
- --sleep: Sleep time between collections in seconds (default: 1)
- --dest: Destination directory for collected data (default: /var/lib/pt-stalk)
- --prefix: Filename prefix for samples
- --daemonize: Run as daemon (default: false)

### MySQL Collector Options
- --mysql-host: MySQL host (default: localhost)
- --mysql-port: MySQL port (default: 3306)
- --mysql-user: MySQL user
- --mysql-password: MySQL password
- --mysql-socket: MySQL socket file
- --mysql-defaults-file: MySQL configuration file

### System Collector Options
- --collect-gdb: Collect GDB stacktraces (default: false)
- --collect-oprofile: Collect OProfile data (default: false)
- --collect-strace: Collect strace data (default: false)
- --collect-tcpdump: Collect tcpdump data (default: false)

### Retention Options
- --retention-time: Days to retain samples (default: 30)
- --retention-count: Number of samples to retain (default: 0)
- --retention-size: Maximum size in MB to retain (default: 0)
- --disk-bytes-free: Minimum bytes free (default: 100MB)
- --disk-pct-free: Minimum percent free (default: 5)

### Notification Options
- --notify-by-email: Email address for notifications
- --verbose: Verbosity level (0-3) (default: 2)

### MongoDB Collector Options
- --mongodb-host: MongoDB host (default: localhost)
- --mongodb-port: MongoDB port (default: 27017)
- --mongodb-user: MongoDB user
- --mongodb-password: MongoDB password

## Output Files

Each collection creates files with the specified prefix and timestamps:
- {prefix}_status.txt: MySQL status variables
- {prefix}_variables.txt: MySQL system variables
- {prefix}_processlist.txt: MySQL process list
- {prefix}_diskstats.txt: System disk statistics
- {prefix}_meminfo.txt: System memory information
- {prefix}_loadavg.txt: System load average
- {prefix}_plugin.txt: Custom plugin output (if configured)
- {prefix}_server_status.txt: MongoDB server status metrics
- {prefix}_current_op.txt: MongoDB currently running operations
- {prefix}_db_stats.txt: MongoDB database statistics