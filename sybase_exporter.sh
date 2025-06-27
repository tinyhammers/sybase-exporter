#!/bin/bash
#
# Sybase Prometheus Exporter
# This script collects metrics from Sybase and exposes them in Prometheus format
# via a simple HTTP server.
#

# Default configuration
PORT=9399
LISTEN_ADDRESS="0.0.0.0"

# Sybase configuration
SYBASE="/usr/local/sybase"
SYBASE_SERVER="RPASEP02"
SYBASE_USER="datadog"
ZDIR="/opt/zabbixAgent"
PASSWORD_FILE="$ZDIR/.pw"

# Configuration file
CONFIG_FILE="/etc/sybase_exporter.conf"

# Function to print usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -p, --port PORT              Port to listen on (default: 9399)"
    echo "  -a, --address ADDR           Address to listen on (default: 0.0.0.0)"
    echo "  -s, --server SERVER          Sybase server name (default: RPASEP02)"
    echo "  -u, --user USERNAME          Sybase username (default: datadog)"
    echo "  -z, --zdir DIR               Directory containing password file (default: /opt/zabbixAgent)"
    echo "  -c, --config FILE            Configuration file (default: /etc/sybase_exporter.conf)"
    echo "  -h, --help                   Display this help message and exit"
    exit 1
}

# Load configuration file if it exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -a|--address)
            LISTEN_ADDRESS="$2"
            shift 2
            ;;
        -s|--server)
            SYBASE_SERVER="$2"
            shift 2
            ;;
        -u|--user)
            SYBASE_USER="$2"
            shift 2
            ;;
        -z|--zdir)
            ZDIR="$2"
            PASSWORD_FILE="$ZDIR/.pw"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
            else
                echo "Warning: Configuration file $CONFIG_FILE not found." >&2
            fi
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Function to collect metrics
collect_metrics() {
    # Set up Sybase environment
    export SYBASE="$SYBASE"
    . "$SYBASE/SYBASE.sh"
    
    # Get hostname for labels
    HOSTNAME=$(hostname)
    
    # Get password
    if [ -f "$PASSWORD_FILE" ]; then
        PASSWORD=$(cat "$PASSWORD_FILE")
    else
        echo "Error: Password file not found at $PASSWORD_FILE" >&2
        return 1
    fi
    
    # Start with exporter metrics
    echo "# HELP sybase_exporter_up Whether the Sybase exporter is up (1) or not (0)"
    echo "# TYPE sybase_exporter_up gauge"
    echo "sybase_exporter_up{host=\"$HOSTNAME\"} 1"
    
    # Run sybase_log_used_pct.sh equivalent
    echo "# HELP sybase_log_used_pct Percentage of log space used (over 50%)"
    echo "# TYPE sybase_log_used_pct gauge"
    
    LOG_RESULT=$(isql -U"$SYBASE_USER" -S"$SYBASE_SERVER" -P"$PASSWORD" -w999 -s"|" -b -l 300 -t 300 <<EOF 2>/dev/null | awk -F\| '{print $2}' | awk '{print $1}'
set nocount on
go
set rowcount 1
go
select @@servername+".."+db_name(d.dbid) as db_name,
ceiling(sum(case when u.segmap = 4 then u.size/1048576.*@@maxpagesize end)) as log_size,
ceiling(sum(case when u.segmap = 4 then u.size/1048576.*@@maxpagesize end) - lct_admin('logsegment_freepages',d.dbid)/1048576.*@@maxpagesize) as log_used,
ceiling(100 * (1 - 1.0 * lct_admin('logsegment_freepages',d.dbid) / sum(case when u.segmap in (4, 7) then u.size end))) as log_used_pct
from master..sysdatabases d, master..sysusages u
where u.dbid = d.dbid  and d.status != 256 and u.segmap = 4
and d.status2&16!=16
group by d.dbid
having ceiling(100 * (1 - 1.0 * lct_admin('logsegment_freepages',d.dbid) / sum(case when u.segmap in (4, 7) then u.size end))) >50
order by ceiling(100 * (1 - 1.0 * lct_admin('logsegment_freepages',d.dbid) / sum(case when u.segmap in (4, 7) then u.size end))) DESC
go
EOF
)
    
    # Check if the result contains error messages
    if [[ "$LOG_RESULT" == *"CT-LIBRARY error"* || "$LOG_RESULT" == *"Error"* ]]; then
        echo "# Error connecting to database server for log usage metrics"
        echo "sybase_log_used_pct{host=\"$HOSTNAME\"} 0"
    elif [ -n "$LOG_RESULT" ] && [[ "$LOG_RESULT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "sybase_log_used_pct{host=\"$HOSTNAME\"} $LOG_RESULT"
    else
        echo "# No log usage metrics available or no logs over 50% full"
        echo "sybase_log_used_pct{host=\"$HOSTNAME\"} 0"
    fi
    
    # Run sybase_ASE_db_space.sh equivalent
    echo "# HELP sybase_db_used_pct Percentage of database space used"
    echo "# TYPE sybase_db_used_pct gauge"
    
    DB_SPACE_RESULT=$(isql -U"$SYBASE_USER" -S"$SYBASE_SERVER" -P"$PASSWORD" -w999 -s"|" -b -l 300 -t 300 <<EOF 2>/dev/null
set nocount on
go
select db_name(dbid),
       str((sum(size) - sum(curunreservedpgs(dbid, lstart, unreservedpgs)) * 1.0) * 100 / sum(size), 6, 2)
from master..sysusages
where segmap = 3
group by db_name(dbid)
order by 2 desc
go
EOF
)
    
    # Check if the result contains error messages
    if [[ "$DB_SPACE_RESULT" == *"CT-LIBRARY error"* || "$DB_SPACE_RESULT" == *"Error"* ]]; then
        echo "# Error connecting to database server for db space metrics"
        echo "sybase_db_used_pct{host=\"$HOSTNAME\"} 0"
    elif [ -n "$DB_SPACE_RESULT" ]; then
        echo "$DB_SPACE_RESULT" | while read -r line; do
            # Strip leading/trailing pipes and squeeze excess whitespace
            cleaned=$(echo "$line" | sed 's/^|//; s/|$//; s/ \{2,\}/ /g' | sed 's/ *| */|/g')
            
            # Skip header lines, empty lines, and error messages
            if [[ -n "$cleaned" && "$cleaned" != *"---"* && "$cleaned" != *"CT-LIBRARY error"* && "$cleaned" != *"Error"* ]]; then
                # Split into database and percentage
                db=$(echo "$cleaned" | cut -d'|' -f1 | xargs)
                pct=$(echo "$cleaned" | cut -d'|' -f2 | xargs)
                
                # Check if pct is a valid number
                if [ -n "$db" ] && [ -n "$pct" ] && [[ "$pct" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    echo "sybase_db_used_pct{host=\"$HOSTNAME\",database=\"$db\"} $pct"
                fi
            fi
        done
    else
        echo "# No database space metrics available"
        echo "sybase_db_used_pct{host=\"$HOSTNAME\"} 0"
    fi
    
    # Run check_ASE_user_conn.sh equivalent
    echo "# HELP sybase_user_connections Number of user connections to Sybase"
    echo "# TYPE sybase_user_connections gauge"
    
    USER_CONN_RESULT=$(isql -U"$SYBASE_USER" -S"$SYBASE_SERVER" -P"$PASSWORD" -w999 -s"|" -b -l 300 -t 300 <<EOF 2>/dev/null | grep 'number of user connection' | awk -F\| '{print $4}' | awk '{print $1}'
set nocount on
go
sp_monitorconfig 'number of user connection'
go
EOF
)
    
    # Check if the result contains error messages
    if [[ "$USER_CONN_RESULT" == *"CT-LIBRARY error"* || "$USER_CONN_RESULT" == *"Error"* ]]; then
        echo "# Error connecting to database server for user connections metrics"
        echo "sybase_user_connections{host=\"$HOSTNAME\"} 0"
    elif [ -n "$USER_CONN_RESULT" ] && [[ "$USER_CONN_RESULT" =~ ^[0-9]+$ ]]; then
        echo "sybase_user_connections{host=\"$HOSTNAME\"} $USER_CONN_RESULT"
    else
        echo "# No user connections metrics available"
        echo "sybase_user_connections{host=\"$HOSTNAME\"} 0"
    fi
    
    # Run check_ASE_long_running.sh equivalent
    echo "# HELP sybase_long_running_queries Number of long-running queries (>600 seconds)"
    echo "# TYPE sybase_long_running_queries gauge"
    
    LONG_RUNNING_RESULT=$(isql -U"$SYBASE_USER" -S"$SYBASE_SERVER" -P"$PASSWORD" -w999 -s"|" -b -l 300 -t 300 <<EOF 2>/dev/null | awk -F\| '{print $2}' | awk '{print $1}'
set nocount on
go
select count(*) from master..syslogshold ps, master..sysdatabases db where db.dbid=ps.dbid and ps.xloid>0 and ps.dbid>1 and datediff(ss,ps.starttime,getdate()) >600
go
EOF
)
    
    # Check if the result contains error messages
    if [[ "$LONG_RUNNING_RESULT" == *"CT-LIBRARY error"* || "$LONG_RUNNING_RESULT" == *"Error"* ]]; then
        echo "# Error connecting to database server for long running queries metrics"
        echo "sybase_long_running_queries{host=\"$HOSTNAME\"} 0"
    elif [ -n "$LONG_RUNNING_RESULT" ] && [[ "$LONG_RUNNING_RESULT" =~ ^[0-9]+$ ]]; then
        echo "sybase_long_running_queries{host=\"$HOSTNAME\"} $LONG_RUNNING_RESULT"
    else
        echo "# No long running queries metrics available"
        echo "sybase_long_running_queries{host=\"$HOSTNAME\"} 0"
    fi
    
    # Run check_ASE_used_locks.sh equivalent
    echo "# HELP sybase_used_locks Number of used locks in Sybase"
    echo "# TYPE sybase_used_locks gauge"
    
    USED_LOCKS_RESULT=$(isql -U"$SYBASE_USER" -S"$SYBASE_SERVER" -P"$PASSWORD" -w999 -s"|" -b -l 300 -t 300 <<EOF 2>/dev/null | awk -F\| '{print $2}' | awk '{print $1}'
set nocount on
go
select count(*) from master..syslocks
go
EOF
)
    
    # Check if the result contains error messages
    if [[ "$USED_LOCKS_RESULT" == *"CT-LIBRARY error"* || "$USED_LOCKS_RESULT" == *"Error"* ]]; then
        echo "# Error connecting to database server for used locks metrics"
        echo "sybase_used_locks{host=\"$HOSTNAME\"} 0"
    elif [ -n "$USED_LOCKS_RESULT" ] && [[ "$USED_LOCKS_RESULT" =~ ^[0-9]+$ ]]; then
        echo "sybase_used_locks{host=\"$HOSTNAME\"} $USED_LOCKS_RESULT"
    else
        echo "# No used locks metrics available"
        echo "sybase_used_locks{host=\"$HOSTNAME\"} 0"
    fi
    
    # Run check_ASE_db_status.sh equivalent
    echo "# HELP sybase_db_status Database status (1=problem, 0=ok)"
    echo "# TYPE sybase_db_status gauge"
    
    DB_STATUS_RESULT=$(isql -U"$SYBASE_USER" -S"$SYBASE_SERVER" -P"$PASSWORD" -w999 -s"|" -b -l 300 -t 300 <<EOF 2>/dev/null | awk -F\| '{print $2}' | awk '{print $1}'
set nocount on
go
set rowcount 1
go
select @@servername+".."+name
from master..sysdatabases
where durability =1
and (status & 32!=0
or status & 64!=0
or status & 256!=0
or status & 1024!=0
or status2 & 16!=0
or status2 & 32!=0
or status2 & 512!=0
or status2 & 1024!=0
or status3 & 1!=0
or status3 & 2!=0
or status3 & 4!=0
or status3 & 8!=0
or status3 & 64!=0
or status3 & 128!=0
or status3 & 256!=0
or status3 & 512!=0
or status3 & 4096!=0
or status3 & 8192!=0)
order by dbid
go
EOF
)
    
    # Check if the result contains error messages
    if [[ "$DB_STATUS_RESULT" == *"CT-LIBRARY error"* || "$DB_STATUS_RESULT" == *"Error"* ]]; then
        echo "# Error connecting to database server for database status metrics"
        echo "sybase_db_status{host=\"$HOSTNAME\"} 0"
    elif [ -n "$DB_STATUS_RESULT" ]; then
        echo "sybase_db_status{host=\"$HOSTNAME\"} 1"
        echo "sybase_db_status{host=\"$HOSTNAME\",database=\"$DB_STATUS_RESULT\"} 1"
    else
        echo "# No database status issues detected"
        echo "sybase_db_status{host=\"$HOSTNAME\"} 0"
    fi
}

# Function to generate HTTP response
generate_response() {
    # Collect metrics
    metrics=$(collect_metrics)
    
    # Calculate content length
    content_length=$(echo -n "$metrics" | wc -c)
    
    # Generate HTTP response with proper headers
    echo -e "HTTP/1.1 200 OK\r"
    echo -e "Content-Type: text/plain; version=0.0.4\r"
    echo -e "Content-Length: $content_length\r"
    echo -e "Connection: close\r"
    echo -e "\r"
    echo -n "$metrics"
}

# Main function
main() {
    # Check if netcat is available
    if ! command -v nc >/dev/null 2>&1; then
        echo "Error: netcat (nc) is not installed. Please install it to use this exporter." >&2
        exit 1
    fi
    
    echo "Starting Sybase Prometheus Exporter on $LISTEN_ADDRESS:$PORT"
    
    # Create a temporary file for the response
    RESPONSE_FILE=$(mktemp)
    
    # Trap to clean up on exit
    trap "rm -f $RESPONSE_FILE" EXIT
    
    # Loop to handle requests
    while true; do
        # Generate the HTTP response and save it to the temporary file
        {
            # Collect metrics
            metrics=$(collect_metrics)
            
            # Calculate content length
            content_length=$(echo -n "$metrics" | wc -c)
            
            # Generate HTTP response with proper headers
            echo -e "HTTP/1.1 200 OK\r"
            echo -e "Content-Type: text/plain; version=0.0.4\r"
            echo -e "Content-Length: $content_length\r"
            echo -e "Connection: close\r"
            echo -e "\r"
            echo -n "$metrics"
        } > "$RESPONSE_FILE"
        
        # Use netcat to listen for a connection and send the response
        # The -l option is for listening mode
        # We redirect the response file to netcat's input
        nc -l "$LISTEN_ADDRESS" "$PORT" < "$RESPONSE_FILE"
        
        # Small delay to ensure the socket is released
        sleep 0.1
    done
}

# Run the main function
main
