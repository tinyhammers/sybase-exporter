# Sybase Prometheus Exporter

A Prometheus exporter for Sybase ASE metrics. This exporter collects various metrics from Sybase ASE databases and exposes them in Prometheus format via a simple HTTP server.

## Metrics

The exporter collects the following metrics:

- `sybase_log_used_pct` - Percentage of log space used (over 50%)
- `sybase_db_used_pct` - Percentage of database space used
- `sybase_user_connections` - Number of user connections to Sybase
- `sybase_long_running_queries` - Number of long-running queries (>600 seconds)
- `sybase_used_locks` - Number of used locks in Sybase
- `sybase_db_status` - Database status (1=problem, 0=ok)
- `sybase_exporter_up` - Whether the Sybase exporter is up (1) or not (0)

All metrics include a `host` label with the hostname of the machine running the exporter.

## Requirements

- Bash
- Netcat (nc) - Used for creating the HTTP server
- Sybase client tools (isql)

## Installation

### Manual Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/sybase_exporter.git
   cd sybase_exporter
   ```

2. Install the exporter:
   ```
   make install
   ```

3. Edit the configuration file:
   ```
   vi /etc/sybase_exporter.conf
   ```

4. Start the service:
   ```
   systemctl start sybase_exporter
   ```

5. Enable the service to start at boot:
   ```
   systemctl enable sybase_exporter
   ```

### RPM Installation

1. Build the RPM package:
   ```
   make rpm
   ```

2. Install the RPM package:
   ```
   rpm -ivh sybase_exporter-1.0.0-1.el7.noarch.rpm
   ```

3. Edit the configuration file:
   ```
   vi /etc/sybase_exporter.conf
   ```

4. Start the service:
   ```
   systemctl start sybase_exporter
   ```

5. Enable the service to start at boot:
   ```
   systemctl enable sybase_exporter
   ```

## Usage

### Command Line Options

```
Usage: sybase_exporter [OPTIONS]
Options:
  -p, --port PORT              Port to listen on (default: 9399)
  -a, --address ADDR           Address to listen on (default: 0.0.0.0)
  -s, --server SERVER          Sybase server name (default: RPASEP02)
  -u, --user USERNAME          Sybase username (default: datadog)
  -z, --zdir DIR               Directory containing password file (default: /opt/zabbixAgent)
  -c, --config FILE            Configuration file (default: /etc/sybase_exporter.conf)
  -h, --help                   Display this help message and exit
```

### Configuration File

The exporter can be configured using a configuration file. The default location is `/etc/sybase_exporter.conf`. Here's an example configuration:

```
# HTTP server settings
PORT=9399
LISTEN_ADDRESS="0.0.0.0"

# Sybase configuration
SYBASE="/usr/local/sybase"
SYBASE_SERVER="RPASEP02"
SYBASE_USER="datadog"
ZDIR="/opt/zabbixAgent"
PASSWORD_FILE="$ZDIR/.pw"
```

### Prometheus Configuration

Add the following to your Prometheus configuration to scrape metrics from the exporter:

```yaml
scrape_configs:
  - job_name: 'sybase'
    static_configs:
      - targets: ['localhost:9399']
```

## HTTP Server Implementation

The exporter uses `netcat` (nc) to create a simple HTTP server. Netcat is a lightweight networking utility that is available on most Unix-like systems.

### Simple and Reliable Approach

- **Compatibility**: Works with all versions of netcat (both GNU and BSD variants)
- **Simplicity**: Uses a straightforward approach that doesn't rely on specific options
- **Reliability**: Properly handles connection termination between requests
- **Portability**: Works across different operating systems and distributions

The implementation uses a temporary file approach with netcat:
- Generates the HTTP response and saves it to a temporary file
- Uses netcat to listen for a connection and send the response
- Adds a small delay to ensure the socket is released between connections
- Handles proper cleanup on exit

This ensures that each connection is handled independently and is properly closed after the response is sent.

## Building the RPM Package

To build the RPM package, simply run the provided build script:

```bash
./build_rpm.sh
```

This script will:
1. Create a properly structured tarball in `~/rpmbuild/SOURCES/`
2. Copy the spec file to `~/rpmbuild/SPECS/`
3. Build the RPM package
4. Display the location of the built RPM package

The RPM package will be created in `~/rpmbuild/RPMS/noarch/`.

## License

MIT
