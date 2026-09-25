#!/usr/bin/env bash

# ============================================================
# Linux System Health, Diagnostics & Resource Monitor
# Version 3.1
# Ubuntu / WSL2 / Linux
# ============================================================

VERSION="3.1"

set -u
set -o pipefail

# ============================================================
# PATHS
# ============================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="$BASE_DIR/logs"
REPORT_DIR="$BASE_DIR/reports"

SYSTEM_LOG="$LOG_DIR/system.log"
ALERT_LOG="$LOG_DIR/alerts.log"
HISTORY_FILE="$LOG_DIR/history.csv"

LOCK_FILE="/tmp/linux-system-monitor.lock"

# ============================================================
# DEFAULT CONFIGURATION
# ============================================================

CPU_WARNING=70
CPU_CRITICAL=90

RAM_WARNING=70
RAM_CRITICAL=90

SWAP_WARNING=70
SWAP_CRITICAL=90

DISK_WARNING=75
DISK_CRITICAL=90

LOAD_WARNING=1.0
LOAD_CRITICAL=2.0

REFRESH_INTERVAL=3

NETWORK_TEST_HOST="1.1.1.1"
DNS_TEST_HOST="example.com"

LOG_MAX_SIZE_KB=1024

# ============================================================
# COLORS
# ============================================================

if [ -t 1 ]; then
    RESET="\033[0m"
    BOLD="\033[1m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    CYAN="\033[36m"
else
    RESET=""
    BOLD=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
fi

# ============================================================
# SIGNAL HANDLING
# ============================================================

cleanup()
{
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

handle_interrupt()
{
    echo ""
    echo -e "${YELLOW}Monitoring stopped.${RESET}"
    cleanup
    exit 130
}

trap cleanup EXIT
trap handle_interrupt INT TERM

# ============================================================
# INITIALIZATION
# ============================================================

initialize()
{
    mkdir -p "$LOG_DIR"
    mkdir -p "$REPORT_DIR"

    if [ ! -f "$SYSTEM_LOG" ]; then
        touch "$SYSTEM_LOG"
    fi

    if [ ! -f "$ALERT_LOG" ]; then
        touch "$ALERT_LOG"
    fi

    if [ ! -f "$HISTORY_FILE" ]; then
        echo "timestamp,cpu_percent,ram_percent,swap_percent,disk_percent,load_1m,processes,health" \
            > "$HISTORY_FILE"
    fi
}

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

pause_screen()
{
    echo ""
    read -r -p "Press Enter to continue..."
}

print_header()
{
    clear

    echo -e "${CYAN}${BOLD}"
    echo "======================================================================"
    echo "             LINUX SYSTEM HEALTH & DIAGNOSTICS MONITOR"
    echo "======================================================================"
    echo -e "${RESET}"
}

print_section()
{
    echo ""
    echo -e "${BLUE}${BOLD}$1${RESET}"
    echo "----------------------------------------------------------------------"
}

print_ok()
{
    echo -e "${GREEN}[ OK ]${RESET} $1"
}

print_warning()
{
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

print_critical()
{
    echo -e "${RED}[CRIT]${RESET} $1"
}

print_info()
{
    echo -e "${CYAN}[INFO]${RESET} $1"
}

is_integer()
{
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_number()
{
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

# ============================================================
# CONFIGURATION
# ============================================================

load_configuration()
{
    local config_file="$BASE_DIR/config.conf"

    if [ -f "$config_file" ]; then
        # shellcheck disable=SC1090
        source "$config_file"
    fi

    validate_configuration
}

validate_configuration()
{
    is_integer "$CPU_WARNING" || CPU_WARNING=70
    is_integer "$CPU_CRITICAL" || CPU_CRITICAL=90

    is_integer "$RAM_WARNING" || RAM_WARNING=70
    is_integer "$RAM_CRITICAL" || RAM_CRITICAL=90

    is_integer "$SWAP_WARNING" || SWAP_WARNING=70
    is_integer "$SWAP_CRITICAL" || SWAP_CRITICAL=90

    is_integer "$DISK_WARNING" || DISK_WARNING=75
    is_integer "$DISK_CRITICAL" || DISK_CRITICAL=90

    is_number "$LOAD_WARNING" || LOAD_WARNING=1.0
    is_number "$LOAD_CRITICAL" || LOAD_CRITICAL=2.0

    is_integer "$REFRESH_INTERVAL" || REFRESH_INTERVAL=3
    is_integer "$LOG_MAX_SIZE_KB" || LOG_MAX_SIZE_KB=1024

    if (( REFRESH_INTERVAL < 1 )); then
        REFRESH_INTERVAL=3
    fi

    if (( CPU_WARNING >= CPU_CRITICAL )); then
        CPU_WARNING=70
        CPU_CRITICAL=90
    fi

    if (( RAM_WARNING >= RAM_CRITICAL )); then
        RAM_WARNING=70
        RAM_CRITICAL=90
    fi

    if (( SWAP_WARNING >= SWAP_CRITICAL )); then
        SWAP_WARNING=70
        SWAP_CRITICAL=90
    fi

    if (( DISK_WARNING >= DISK_CRITICAL )); then
        DISK_WARNING=75
        DISK_CRITICAL=90
    fi
}

# ============================================================
# DEPENDENCY CHECK
# ============================================================

check_dependencies()
{
    local required_commands=(
        awk
        sed
        grep
        head
        tail
        ps
        free
        df
        date
        hostname
        uptime
        uname
        find
        id
        who
    )

    local missing=0

    for cmd in "${required_commands[@]}"
    do
        if ! command_exists "$cmd"; then
            echo -e "${RED}Missing command:${RESET} $cmd"
            missing=1
        fi
    done

    return "$missing"
}

# ============================================================
# LOGGING
# ============================================================

log_event()
{
    local message="$1"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | $message" >> "$SYSTEM_LOG"
}

log_alert()
{
    local severity="$1"
    local metric="$2"
    local value="$3"
    local threshold="$4"
    local message="$5"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | $severity | $metric | value=$value | threshold=$threshold | $message" \
        >> "$ALERT_LOG"
}

rotate_logs()
{
    local max_bytes
    max_bytes=$((LOG_MAX_SIZE_KB * 1024))

    if [ -f "$SYSTEM_LOG" ]; then
        local size
        size=$(wc -c < "$SYSTEM_LOG")

        if (( size > max_bytes )); then
            mv "$SYSTEM_LOG" "$SYSTEM_LOG.1"
            touch "$SYSTEM_LOG"
        fi
    fi

    if [ -f "$ALERT_LOG" ]; then
        local alert_size
        alert_size=$(wc -c < "$ALERT_LOG")

        if (( alert_size > max_bytes )); then
            mv "$ALERT_LOG" "$ALERT_LOG.1"
            touch "$ALERT_LOG"
        fi
    fi
}

# ============================================================
# SYSTEM INFORMATION
# ============================================================

get_hostname()
{
    hostname 2>/dev/null || echo "Unknown"
}

get_os()
{
    if [ -f /etc/os-release ]; then
        awk -F= '
        /^PRETTY_NAME=/ {
            gsub(/"/,"",$2)
            print $2
            exit
        }' /etc/os-release
    else
        echo "Unknown"
    fi
}

get_kernel()
{
    uname -r 2>/dev/null || echo "Unknown"
}

get_architecture()
{
    uname -m 2>/dev/null || echo "Unknown"
}

get_cpu_model()
{
    awk -F: '
    /^model name/ {
        gsub(/^[ \t]+/, "", $2)
        print $2
        exit
    }' /proc/cpuinfo 2>/dev/null
}

get_cpu_cores()
{
    grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "Unknown"
}

get_uptime()
{
    uptime -p 2>/dev/null || echo "Unknown"
}

get_load_average()
{
    awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null
}

get_load_1m()
{
    awk '{print $1}' /proc/loadavg 2>/dev/null
}

get_logged_users()
{
    who 2>/dev/null | wc -l
}

get_current_user()
{
    id -un 2>/dev/null || echo "Unknown"
}

get_uid()
{
    id -u 2>/dev/null || echo "Unknown"
}

get_gid()
{
    id -g 2>/dev/null || echo "Unknown"
}

get_shell()
{
    printf '%s\n' "${SHELL:-Unknown}"
}

get_process_count()
{
    ps -e --no-headers 2>/dev/null | wc -l
}

# ============================================================
# CPU MONITORING
# ============================================================

read_cpu_stats()
{
    awk '
    /^cpu / {
        print $2,$3,$4,$5,$6,$7,$8,$9
        exit
    }' /proc/stat 2>/dev/null
}

get_cpu_from_proc()
{
    local first
    local second

    first=$(read_cpu_stats)

    sleep 0.15

    second=$(read_cpu_stats)

    if [ -z "$first" ] || [ -z "$second" ]; then
        echo "0.0"
        return
    fi

    awk -v a="$first" -v b="$second" '
    BEGIN {
        split(a,x," ")
        split(b,y," ")

        idle1=x[4]+x[5]
        idle2=y[4]+y[5]

        total1=0
        total2=0

        for(i=1;i<=8;i++) {
            total1+=x[i]
            total2+=y[i]
        }

        total_diff=total2-total1
        idle_diff=idle2-idle1

        if(total_diff > 0)
            printf "%.1f", ((total_diff-idle_diff)/total_diff)*100
        else
            printf "0.0"
    }'
}

get_per_core_cpu()
{
    local before
    local after

    before=$(grep '^cpu[0-9]' /proc/stat 2>/dev/null)

    sleep 0.15

    after=$(grep '^cpu[0-9]' /proc/stat 2>/dev/null)

    if [ -z "$before" ] || [ -z "$after" ]; then
        echo "Per-core CPU information unavailable."
        return
    fi

    awk '
    NR==FNR {
        old[$1]=$0
        next
    }

    {
        split(old[$1],a," ")
        split($0,b," ")

        old_total=0
        new_total=0

        for(i=2;i<=9;i++) {
            old_total+=a[i]
            new_total+=b[i]
        }

        old_idle=a[5]+a[6]
        new_idle=b[5]+b[6]

        total_diff=new_total-old_total
        idle_diff=new_idle-old_idle

        if(total_diff > 0)
            usage=((total_diff-idle_diff)/total_diff)*100
        else
            usage=0

        printf "%-8s %.1f%%\n",$1,usage
    }
    ' <(printf '%s\n' "$before") <(printf '%s\n' "$after")
}

# ============================================================
# MEMORY
# ============================================================

get_ram_total_kb()
{
    awk '/^MemTotal:/ {print $2}' /proc/meminfo
}

get_ram_available_kb()
{
    awk '/^MemAvailable:/ {print $2}' /proc/meminfo
}

get_ram_free_kb()
{
    awk '/^MemFree:/ {print $2}' /proc/meminfo
}

get_ram_used_kb()
{
    awk '
    /^MemTotal:/ {total=$2}
    /^MemAvailable:/ {available=$2}

    END {
        if(total > 0)
            print total-available
        else
            print 0
    }' /proc/meminfo
}

get_ram_percent()
{
    awk '
    /^MemTotal:/ {total=$2}
    /^MemAvailable:/ {available=$2}

    END {
        if(total > 0)
            printf "%.1f", ((total-available)/total)*100
        else
            print "0.0"
    }' /proc/meminfo
}

get_swap_total_kb()
{
    awk '/^SwapTotal:/ {print $2}' /proc/meminfo
}

get_swap_free_kb()
{
    awk '/^SwapFree:/ {print $2}' /proc/meminfo
}

get_swap_used_kb()
{
    awk '
    /^SwapTotal:/ {total=$2}
    /^SwapFree:/ {free=$2}

    END {
        print total-free
    }' /proc/meminfo
}

get_swap_percent()
{
    awk '
    /^SwapTotal:/ {total=$2}
    /^SwapFree:/ {free=$2}

    END {
        if(total > 0)
            printf "%.1f", ((total-free)/total)*100
        else
            print "0.0"
    }' /proc/meminfo
}

human_kb()
{
    local kb="$1"

    awk -v kb="$kb" '
    BEGIN {
        if(kb >= 1073741824)
            printf "%.2f TB", kb/1073741824
        else if(kb >= 1048576)
            printf "%.2f GB", kb/1048576
        else if(kb >= 1024)
            printf "%.2f MB", kb/1024
        else
            printf "%d KB", kb
    }'
}

# ============================================================
# DISK
# ============================================================

get_root_disk_percent()
{
    df / 2>/dev/null |
        awk '
        NR==2 {
            gsub("%","",$5)
            print $5
        }'
}

show_filesystems()
{
    df -h 2>/dev/null
}

# ============================================================
# DISK I/O
# ============================================================

show_disk_io()
{
    if [ ! -r /proc/diskstats ]; then
        echo "Disk I/O statistics unavailable on this system."
        return
    fi

    echo ""
    printf "%-12s %-15s %-15s %-18s %-18s\n" \
        "DEVICE" "READ OPS" "WRITE OPS" "SECTORS READ" "SECTORS WRITE"

    echo "----------------------------------------------------------------------"

    awk '
    $3 !~ /^(loop|ram|sr|fd)/ {
        printf "%-12s %-15s %-15s %-18s %-18s\n",
        $3,$4,$8,$6,$10
    }' /proc/diskstats
}

# ============================================================
# PROCESS MONITORING
# ============================================================

show_top_cpu_processes()
{
    ps -eo pid,ppid,user,state,comm,%cpu,%mem --sort=-%cpu 2>/dev/null |
        head -16
}

show_top_memory_processes()
{
    ps -eo pid,ppid,user,state,comm,%cpu,%mem --sort=-%mem 2>/dev/null |
        head -16
}

show_process_tree()
{
    if command_exists pstree; then
        pstree -p 2>/dev/null | head -80
    else
        ps -eo pid,ppid,user,comm --forest 2>/dev/null | head -80
    fi
}

show_zombie_processes()
{
    local zombies

    zombies=$(ps -eo pid,ppid,user,state,comm 2>/dev/null |
        awk '$4 ~ /^Z/')

    if [ -n "$zombies" ]; then
        echo "$zombies"
        return 1
    fi

    return 0
}

show_process_details()
{
    local pid="$1"

    if ! is_integer "$pid" || (( pid <= 0 )); then
        echo "Invalid PID."
        return 1
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Process does not exist or cannot be accessed."
        return 1
    fi

    ps -p "$pid" \
        -o pid,ppid,user,group,state,etime,%cpu,%mem,comm,args \
        2>/dev/null
}

search_process()
{
    print_header

    print_section "PROCESS SEARCH"

    read -r -p "Enter process name: " process_name

    if [ -z "$process_name" ]; then
        echo "Process name cannot be empty."
        pause_screen
        return
    fi

    echo ""

    ps -eo pid,ppid,user,state,comm,%cpu,%mem,args 2>/dev/null |
        awk -v search="$process_name" '
        NR==1 || index(tolower($0),tolower(search)) > 0
        '

    pause_screen
}

# ============================================================
# PROCESS CONTROL
# ============================================================

process_control()
{
    print_header

    print_section "SAFE PROCESS CONTROL"

    read -r -p "Enter PID: " pid

    if ! is_integer "$pid"; then
        echo "Invalid PID."
        pause_screen
        return
    fi

    if (( pid <= 1 )); then
        echo "For safety, PID 0 and PID 1 cannot be controlled."
        pause_screen
        return
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Process does not exist or permission is denied."
        pause_screen
        return
    fi

    echo ""
    echo "Selected process:"
    show_process_details "$pid"

    echo ""
    echo "Signal options:"
    echo "1. SIGTERM - Graceful termination request"
    echo "2. SIGHUP  - Reload/re-read configuration"
    echo "3. SIGSTOP - Pause process"
    echo "4. SIGCONT - Continue process"
    echo "5. SIGKILL - Force termination"
    echo "6. Cancel"

    echo ""

    read -r -p "Select signal: " signal_choice

    local signal=""

    case "$signal_choice" in
        1) signal="TERM" ;;
        2) signal="HUP" ;;
        3) signal="STOP" ;;
        4) signal="CONT" ;;
        5) signal="KILL" ;;
        6)
            echo "Cancelled."
            pause_screen
            return
            ;;
        *)
            echo "Invalid selection."
            pause_screen
            return
            ;;
    esac

    echo ""
    echo "You are about to send SIG$signal to PID $pid."

    read -r -p "Confirm? (y/N): " confirmation

    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        pause_screen
        return
    fi

    if kill "-$signal" "$pid" 2>/dev/null; then
        print_ok "SIG$signal sent to PID $pid."
        log_event "Signal SIG$signal sent to PID=$pid"
    else
        print_critical "Unable to send SIG$signal."
        log_event "Failed to send SIG$signal to PID=$pid"
    fi

    pause_screen
}

# ============================================================
# NETWORK
# ============================================================

get_ip_addresses()
{
    if command_exists ip; then
        ip -br addr 2>/dev/null
    else
        echo "ip command unavailable."
    fi
}

get_default_gateway()
{
    if command_exists ip; then
        ip route 2>/dev/null |
            awk '/default/ {print $3; exit}'
    fi
}

get_dns_servers()
{
    if [ -f /etc/resolv.conf ]; then
        awk '/^nameserver/ {print $2}' /etc/resolv.conf
    else
        echo "Unavailable"
    fi
}

show_routes()
{
    if command_exists ip; then
        ip route 2>/dev/null
    else
        echo "Routing information unavailable."
    fi
}

show_connections()
{
    if command_exists ss; then
        ss -tun 2>/dev/null
    else
        echo "ss command unavailable."
    fi
}

show_listening_ports()
{
    if command_exists ss; then
        ss -tuln 2>/dev/null
    else
        echo "ss command unavailable."
    fi
}

# ============================================================
# NETWORK TESTS
# ============================================================

test_gateway()
{
    local gateway

    gateway=$(get_default_gateway)

    if [ -z "$gateway" ]; then
        echo "NO_GATEWAY"
        return 1
    fi

    if command_exists ping &&
        ping -c 1 -W 2 "$gateway" >/dev/null 2>&1
    then
        echo "OK"
        return 0
    fi

    echo "FAILED"
    return 1
}

test_dns()
{
    if command_exists getent; then
        if getent hosts "$DNS_TEST_HOST" >/dev/null 2>&1; then
            echo "OK"
            return 0
        fi
    fi

    if command_exists nslookup; then
        if nslookup "$DNS_TEST_HOST" >/dev/null 2>&1; then
            echo "OK"
            return 0
        fi
    fi

    echo "FAILED"
    return 1
}

test_internet()
{
    if ! command_exists ping; then
        echo "UNAVAILABLE"
        return 2
    fi

    if ping -c 1 -W 2 "$NETWORK_TEST_HOST" >/dev/null 2>&1; then
        echo "OK"
        return 0
    fi

    echo "FAILED"
    return 1
}

get_latency()
{
    if ! command_exists ping; then
        echo "N/A"
        return
    fi

    local latency

    latency=$(ping -c 1 -W 2 "$NETWORK_TEST_HOST" 2>/dev/null |
        awk -F'time=' '/time=/{print $2}' |
        awk '{print $1}')

    if [ -n "$latency" ]; then
        echo "$latency ms"
    else
        echo "N/A"
    fi
}

network_diagnostics()
{
    print_header

    print_section "NETWORK DIAGNOSTICS"

    local gateway_status
    local dns_status
    local internet_status

    echo "Default Gateway : $(get_default_gateway)"

    gateway_status=$(test_gateway)

    echo ""
    echo "Gateway Test:"
    if [ "$gateway_status" = "OK" ]; then
        print_ok "Gateway reachable"
    elif [ "$gateway_status" = "NO_GATEWAY" ]; then
        print_warning "No default gateway found"
    else
        print_warning "Gateway unreachable"
    fi

    dns_status=$(test_dns)

    echo ""
    echo "DNS Test:"
    if [ "$dns_status" = "OK" ]; then
        print_ok "DNS resolution working"
    else
        print_warning "DNS resolution failed"
    fi

    internet_status=$(test_internet)

    echo ""
    echo "Internet Test:"
    if [ "$internet_status" = "OK" ]; then
        print_ok "Internet reachable"
    else
        print_warning "Internet unavailable"
    fi

    echo ""
    echo "Latency: $(get_latency)"

    pause_screen
}

# ============================================================
# SERVICES
# ============================================================

get_failed_service_count()
{
    if ! command_exists systemctl; then
        echo "-1"
        return
    fi

    systemctl --failed \
        --no-legend \
        --no-pager \
        2>/dev/null |
        awk 'NF > 0 {count++} END {print count+0}'
}

service_monitor()
{
    print_header

    print_section "SERVICE MONITORING"

    if ! command_exists systemctl; then
        echo "systemctl is unavailable."
        echo "This is normal on some WSL2 configurations."
        pause_screen
        return
    fi

    echo "System State:"
    systemctl is-system-running 2>/dev/null || true

    echo ""
    echo "Failed Services:"
    echo "----------------------------------------------------------------------"

    local failed_count
    failed_count=$(get_failed_service_count)

    if (( failed_count == 0 )); then
        print_ok "No failed services detected."
    elif (( failed_count > 0 )); then
        systemctl --failed --no-pager 2>/dev/null || true
        print_warning "$failed_count failed service(s) detected."
    else
        print_info "Unable to determine failed service count."
    fi

    echo ""
    echo "Active Service Count:"

    systemctl list-units \
        --type=service \
        --state=active \
        --no-legend \
        --no-pager \
        2>/dev/null |
        wc -l

    echo ""
    echo "Inactive Service Count:"

    systemctl list-units \
        --type=service \
        --state=inactive \
        --no-legend \
        --no-pager \
        2>/dev/null |
        wc -l

    pause_screen
}

# ============================================================
# USER INFORMATION
# ============================================================

user_information()
{
    print_header

    print_section "USER INFORMATION"

    echo "Current User : $(get_current_user)"
    echo "UID          : $(get_uid)"
    echo "GID          : $(get_gid)"
    echo "Shell        : $(get_shell)"

    echo ""
    echo "Groups:"
    id -Gn 2>/dev/null || true

    echo ""
    echo "Logged-in Users:"
    echo "----------------------------------------------------------------------"

    who 2>/dev/null || echo "No login session information available."

    echo ""
    echo "Total Sessions: $(get_logged_users)"

    pause_screen
}

# ============================================================
# BASIC SECURITY AUDIT
# ============================================================

security_audit()
{
    print_header

    print_section "BASIC SECURITY AUDIT"

    echo "This is a basic local security check."
    echo "It is NOT a complete security audit."
    echo ""

    echo "Current User:"
    id 2>/dev/null || true

    echo ""

    if [ "$(id -u 2>/dev/null)" = "0" ]; then
        print_warning "Running as root."
    else
        print_ok "Running as a non-root user."
    fi

    echo ""
    echo "SSH Service:"

    if command_exists systemctl; then
        if systemctl is-active --quiet ssh 2>/dev/null ||
            systemctl is-active --quiet sshd 2>/dev/null
        then
            print_info "SSH service appears active."
        else
            print_info "SSH service is not active or unavailable."
        fi
    else
        print_info "systemctl unavailable; SSH service not checked."
    fi

    echo ""
    echo "Listening Ports:"
    echo "----------------------------------------------------------------------"

    if command_exists ss; then
        ss -tuln 2>/dev/null
    else
        echo "ss unavailable."
    fi

    echo ""
    echo "SUID Files in Common System Locations:"
    echo "----------------------------------------------------------------------"

    if command_exists find; then
        find /usr/bin /usr/sbin \
            -xdev \
            -type f \
            -perm -4000 \
            -print 2>/dev/null |
            head -30
    else
        echo "find unavailable."
    fi

    echo ""
    echo "/tmp Permissions:"

    if [ -d /tmp ]; then
        ls -ld /tmp 2>/dev/null
    fi

    pause_screen
}

# ============================================================
# HEALTH ENGINE
# ============================================================

classify_metric()
{
    local value="$1"
    local warning="$2"
    local critical="$3"

    awk -v v="$value" -v w="$warning" -v c="$critical" '
    BEGIN {
        if(v >= c)
            print "CRITICAL"
        else if(v >= w)
            print "WARNING"
        else
            print "NORMAL"
    }'
}

health_status()
{
    local cpu="$1"
    local ram="$2"
    local swap="$3"
    local disk="$4"
    local load="$5"

    local critical=0
    local warning=0

    if awk -v v="$cpu" -v c="$CPU_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        ((critical++))
    elif awk -v v="$cpu" -v w="$CPU_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        ((warning++))
    fi

    if awk -v v="$ram" -v c="$RAM_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        ((critical++))
    elif awk -v v="$ram" -v w="$RAM_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        ((warning++))
    fi

    if awk -v v="$swap" -v c="$SWAP_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        ((critical++))
    elif awk -v v="$swap" -v w="$SWAP_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        ((warning++))
    fi

    if awk -v v="$disk" -v c="$DISK_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        ((critical++))
    elif awk -v v="$disk" -v w="$DISK_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        ((warning++))
    fi

    if awk -v v="$load" -v c="$LOAD_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        ((critical++))
    elif awk -v v="$load" -v w="$LOAD_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        ((warning++))
    fi

    if (( critical > 0 )); then
        echo "CRITICAL"
    elif (( warning > 0 )); then
        echo "WARNING"
    else
        echo "HEALTHY"
    fi
}

show_health_reasons()
{
    local cpu="$1"
    local ram="$2"
    local swap="$3"
    local disk="$4"
    local load="$5"

    local found=0

    if awk -v v="$cpu" -v c="$CPU_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        print_critical "CPU usage is critically high: $cpu%"
        found=1
    elif awk -v v="$cpu" -v w="$CPU_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        print_warning "CPU usage is high: $cpu%"
        found=1
    fi

    if awk -v v="$ram" -v c="$RAM_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        print_critical "RAM usage is critically high: $ram%"
        found=1
    elif awk -v v="$ram" -v w="$RAM_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        print_warning "RAM usage is high: $ram%"
        found=1
    fi

    if awk -v v="$swap" -v c="$SWAP_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        print_critical "Swap usage is critically high: $swap%"
        found=1
    elif awk -v v="$swap" -v w="$SWAP_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        print_warning "Swap usage is high: $swap%"
        found=1
    fi

    if (( disk >= DISK_CRITICAL )); then
        print_critical "Disk usage is critically high: $disk%"
        found=1
    elif (( disk >= DISK_WARNING )); then
        print_warning "Disk usage is high: $disk%"
        found=1
    fi

    if awk -v v="$load" -v c="$LOAD_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        print_critical "Load average is critically high: $load"
        found=1
    elif awk -v v="$load" -v w="$LOAD_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        print_warning "Load average is elevated: $load"
        found=1
    fi

    if (( found == 0 )); then
        print_ok "No resource threshold violations detected."
    fi
}

# ============================================================
# ALERT ENGINE
# ============================================================

check_alerts()
{
    local cpu="$1"
    local ram="$2"
    local swap="$3"
    local disk="$4"
    local load="$5"

    if awk -v v="$cpu" -v c="$CPU_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        log_alert "CRITICAL" "CPU" "$cpu%" "$CPU_CRITICAL%" \
            "CPU usage exceeded critical threshold"
    elif awk -v v="$cpu" -v w="$CPU_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        log_alert "WARNING" "CPU" "$cpu%" "$CPU_WARNING%" \
            "CPU usage exceeded warning threshold"
    fi

    if awk -v v="$ram" -v c="$RAM_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        log_alert "CRITICAL" "RAM" "$ram%" "$RAM_CRITICAL%" \
            "RAM usage exceeded critical threshold"
    elif awk -v v="$ram" -v w="$RAM_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        log_alert "WARNING" "RAM" "$ram%" "$RAM_WARNING%" \
            "RAM usage exceeded warning threshold"
    fi

    if awk -v v="$swap" -v c="$SWAP_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        log_alert "CRITICAL" "SWAP" "$swap%" "$SWAP_CRITICAL%" \
            "Swap usage exceeded critical threshold"
    elif awk -v v="$swap" -v w="$SWAP_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        log_alert "WARNING" "SWAP" "$swap%" "$SWAP_WARNING%" \
            "Swap usage exceeded warning threshold"
    fi

    if (( disk >= DISK_CRITICAL )); then
        log_alert "CRITICAL" "DISK" "$disk%" "$DISK_CRITICAL%" \
            "Disk usage exceeded critical threshold"
    elif (( disk >= DISK_WARNING )); then
        log_alert "WARNING" "DISK" "$disk%" "$DISK_WARNING%" \
            "Disk usage exceeded warning threshold"
    fi

    if awk -v v="$load" -v c="$LOAD_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        log_alert "CRITICAL" "LOAD" "$load" "$LOAD_CRITICAL" \
            "Load average exceeded critical threshold"
    elif awk -v v="$load" -v w="$LOAD_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        log_alert "WARNING" "LOAD" "$load" "$LOAD_WARNING" \
            "Load average exceeded warning threshold"
    fi
}

# ============================================================
# SNAPSHOT COLLECTION
# ============================================================

collect_snapshot()
{
    CPU_VALUE=$(get_cpu_from_proc)
    RAM_VALUE=$(get_ram_percent)
    SWAP_VALUE=$(get_swap_percent)
    DISK_VALUE=$(get_root_disk_percent)
    LOAD_VALUE=$(get_load_1m)
    PROCESS_VALUE=$(get_process_count)

    CPU_VALUE="${CPU_VALUE:-0.0}"
    RAM_VALUE="${RAM_VALUE:-0.0}"
    SWAP_VALUE="${SWAP_VALUE:-0.0}"
    DISK_VALUE="${DISK_VALUE:-0}"
    LOAD_VALUE="${LOAD_VALUE:-0.0}"
    PROCESS_VALUE="${PROCESS_VALUE:-0}"

    HEALTH_VALUE=$(health_status \
        "$CPU_VALUE" \
        "$RAM_VALUE" \
        "$SWAP_VALUE" \
        "$DISK_VALUE" \
        "$LOAD_VALUE")
}

save_snapshot()
{
    collect_snapshot

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$timestamp,$CPU_VALUE,$RAM_VALUE,$SWAP_VALUE,$DISK_VALUE,$LOAD_VALUE,$PROCESS_VALUE,$HEALTH_VALUE" \
        >> "$HISTORY_FILE"

    log_event \
        "SNAPSHOT CPU=$CPU_VALUE% RAM=$RAM_VALUE% SWAP=$SWAP_VALUE% DISK=$DISK_VALUE% LOAD=$LOAD_VALUE PROCESSES=$PROCESS_VALUE HEALTH=$HEALTH_VALUE"

    check_alerts \
        "$CPU_VALUE" \
        "$RAM_VALUE" \
        "$SWAP_VALUE" \
        "$DISK_VALUE" \
        "$LOAD_VALUE"

    rotate_logs
}

# ============================================================
# SYSTEM OVERVIEW
# ============================================================

system_overview()
{
    print_header

    collect_snapshot

    print_section "SYSTEM INFORMATION"

    echo "Hostname          : $(get_hostname)"
    echo "Operating System  : $(get_os)"
    echo "Kernel            : $(get_kernel)"
    echo "Architecture      : $(get_architecture)"
    echo "CPU Model         : $(get_cpu_model)"
    echo "CPU Cores         : $(get_cpu_cores)"
    echo "Uptime            : $(get_uptime)"
    echo "Load Average      : $(get_load_average)"
    echo "Current User      : $(get_current_user)"
    echo "Logged-in Users   : $(get_logged_users)"
    echo "Running Processes : $PROCESS_VALUE"

    print_section "RESOURCE STATUS"

    echo "CPU Usage         : $CPU_VALUE%"
    echo "RAM Usage         : $RAM_VALUE%"
    echo "Swap Usage        : $SWAP_VALUE%"
    echo "Root Disk         : $DISK_VALUE%"
    echo "Load 1m           : $LOAD_VALUE"

    print_section "OVERALL HEALTH"

    case "$HEALTH_VALUE" in
        HEALTHY)
            print_ok "SYSTEM HEALTH: HEALTHY"
            ;;
        WARNING)
            print_warning "SYSTEM HEALTH: WARNING"
            ;;
        CRITICAL)
            print_critical "SYSTEM HEALTH: CRITICAL"
            ;;
    esac

    echo ""
    show_health_reasons \
        "$CPU_VALUE" \
        "$RAM_VALUE" \
        "$SWAP_VALUE" \
        "$DISK_VALUE" \
        "$LOAD_VALUE"

    save_snapshot

    pause_screen
}

# ============================================================
# CPU MONITOR
# ============================================================

cpu_monitor()
{
    print_header

    print_section "CPU MONITOR"

    local cpu
    cpu=$(get_cpu_from_proc)

    echo "Total CPU Usage : $cpu%"
    echo "CPU Cores       : $(get_cpu_cores)"
    echo "CPU Model       : $(get_cpu_model)"
    echo "Load Average    : $(get_load_average)"

    echo ""
    echo "CPU STATISTICS"
    echo "----------------------------------------------------------------------"

    awk '
    /^cpu / {
        printf "User       : %s\n",$2
        printf "Nice       : %s\n",$3
        printf "System     : %s\n",$4
        printf "Idle       : %s\n",$5
        printf "I/O Wait   : %s\n",$6
        printf "IRQ        : %s\n",$7
        printf "Soft IRQ   : %s\n",$8
        printf "Steal      : %s\n",$9
        exit
    }' /proc/stat

    echo ""
    echo "PER-CORE CPU USAGE"
    echo "----------------------------------------------------------------------"

    get_per_core_cpu

    pause_screen
}

# ============================================================
# MEMORY MONITOR
# ============================================================

memory_monitor()
{
    print_header

    print_section "MEMORY MONITOR"

    local total
    local used
    local available
    local free
    local swap_total
    local swap_used
    local swap_free

    total=$(get_ram_total_kb)
    used=$(get_ram_used_kb)
    available=$(get_ram_available_kb)
    free=$(get_ram_free_kb)

    swap_total=$(get_swap_total_kb)
    swap_used=$(get_swap_used_kb)
    swap_free=$(get_swap_free_kb)

    echo "RAM Total       : $(human_kb "$total")"
    echo "RAM Used        : $(human_kb "$used")"
    echo "RAM Available   : $(human_kb "$available")"
    echo "RAM Free        : $(human_kb "$free")"
    echo "RAM Usage       : $(get_ram_percent)%"

    echo ""
    echo "SWAP"
    echo "----------------------------------------------------------------------"

    echo "Swap Total      : $(human_kb "$swap_total")"
    echo "Swap Used       : $(human_kb "$swap_used")"
    echo "Swap Free       : $(human_kb "$swap_free")"
    echo "Swap Usage      : $(get_swap_percent)%"

    echo ""
    echo "KERNEL MEMORY INFORMATION"
    echo "----------------------------------------------------------------------"

    awk '
    /^Buffers:/       {print "Buffers       :", $2, $3}
    /^Cached:/        {print "Cached        :", $2, $3}
    /^SReclaimable:/  {print "Reclaimable   :", $2, $3}
    /^Slab:/          {print "Slab          :", $2, $3}
    ' /proc/meminfo

    pause_screen
}

# ============================================================
# DISK MONITOR
# ============================================================

disk_monitor()
{
    print_header

    print_section "FILESYSTEM MONITOR"

    show_filesystems

    echo ""
    echo "Root Filesystem Usage: $(get_root_disk_percent)%"

    local root_usage
    root_usage=$(get_root_disk_percent)

    if (( root_usage >= DISK_CRITICAL )); then
        print_critical "Root filesystem is critically full."
    elif (( root_usage >= DISK_WARNING )); then
        print_warning "Root filesystem usage is high."
    else
        print_ok "Root filesystem usage is normal."
    fi

    pause_screen
}

# ============================================================
# DISK I/O MONITOR
# ============================================================

disk_io_monitor()
{
    print_header

    print_section "DISK I/O"

    show_disk_io

    pause_screen
}

# ============================================================
# PROCESS MONITOR
# ============================================================

process_monitor()
{
    print_header

    print_section "TOP PROCESSES BY CPU"

    show_top_cpu_processes

    print_section "TOP PROCESSES BY MEMORY"

    show_top_memory_processes

    print_section "PROCESS TREE"

    show_process_tree

    print_section "ZOMBIE PROCESSES"

    if show_zombie_processes; then
        print_ok "No zombie processes detected."
    else
        print_warning "Zombie processes detected."
    fi

    pause_screen
}

# ============================================================
# NETWORK INFORMATION
# ============================================================

network_information()
{
    print_header

    print_section "NETWORK INTERFACES"

    get_ip_addresses

    print_section "DEFAULT GATEWAY"

    get_default_gateway

    print_section "DNS SERVERS"

    get_dns_servers

    print_section "ROUTING TABLE"

    show_routes

    print_section "ACTIVE CONNECTIONS"

    show_connections

    print_section "LISTENING PORTS"

    show_listening_ports

    pause_screen
}

# ============================================================
# HEALTH ANALYSIS
# ============================================================

health_analysis()
{
    print_header

    collect_snapshot

    print_section "HEALTH ANALYSIS"

    echo "CPU Status  : $(classify_metric "$CPU_VALUE" "$CPU_WARNING" "$CPU_CRITICAL")"
    echo "RAM Status  : $(classify_metric "$RAM_VALUE" "$RAM_WARNING" "$RAM_CRITICAL")"
    echo "Swap Status : $(classify_metric "$SWAP_VALUE" "$SWAP_WARNING" "$SWAP_CRITICAL")"
    echo "Disk Status : $(classify_metric "$DISK_VALUE" "$DISK_WARNING" "$DISK_CRITICAL")"
    echo "Load Status : $(classify_metric "$LOAD_VALUE" "$LOAD_WARNING" "$LOAD_CRITICAL")"

    echo ""
    echo "Overall Status:"

    case "$HEALTH_VALUE" in
        HEALTHY)
            print_ok "HEALTHY"
            ;;
        WARNING)
            print_warning "WARNING"
            ;;
        CRITICAL)
            print_critical "CRITICAL"
            ;;
    esac

    echo ""
    echo "Reasons:"
    echo "----------------------------------------------------------------------"

    show_health_reasons \
        "$CPU_VALUE" \
        "$RAM_VALUE" \
        "$SWAP_VALUE" \
        "$DISK_VALUE" \
        "$LOAD_VALUE"

    save_snapshot

    pause_screen
}

# ============================================================
# FULL DIAGNOSTICS
# ============================================================

full_diagnostics()
{
    print_header

    echo -e "${BOLD}Running full system diagnostics...${RESET}"
    echo ""

    local passed=0
    local warnings=0
    local critical=0

    # --------------------------------------------------------
    # 1. SYSTEM
    # --------------------------------------------------------

    echo "1. System Information"

    if [ -r /proc/cpuinfo ] && [ -r /proc/meminfo ]; then
        print_ok "System information available"
        ((passed++))
    else
        print_warning "Some system information unavailable"
        ((warnings++))
    fi

    # --------------------------------------------------------
    # 2. CPU
    # --------------------------------------------------------

    echo ""
    echo "2. CPU"

    local cpu
    cpu=$(get_cpu_from_proc)

    if awk -v v="$cpu" -v c="$CPU_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        print_critical "CPU critical: $cpu%"
        ((critical++))
    elif awk -v v="$cpu" -v w="$CPU_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        print_warning "CPU warning: $cpu%"
        ((warnings++))
    else
        print_ok "CPU normal: $cpu%"
        ((passed++))
    fi

    # --------------------------------------------------------
    # 3. MEMORY
    # --------------------------------------------------------

    echo ""
    echo "3. Memory"

    local ram
    ram=$(get_ram_percent)

    if awk -v v="$ram" -v c="$RAM_CRITICAL" 'BEGIN{exit !(v>=c)}'
    then
        print_critical "RAM critical: $ram%"
        ((critical++))
    elif awk -v v="$ram" -v w="$RAM_WARNING" 'BEGIN{exit !(v>=w)}'
    then
        print_warning "RAM warning: $ram%"
        ((warnings++))
    else
        print_ok "RAM normal: $ram%"
        ((passed++))
    fi

    # --------------------------------------------------------
    # 4. DISK
    # --------------------------------------------------------

    echo ""
    echo "4. Disk"

    local disk
    disk=$(get_root_disk_percent)

    if (( disk >= DISK_CRITICAL )); then
        print_critical "Disk critical: $disk%"
        ((critical++))
    elif (( disk >= DISK_WARNING )); then
        print_warning "Disk warning: $disk%"
        ((warnings++))
    else
        print_ok "Disk normal: $disk%"
        ((passed++))
    fi

    # --------------------------------------------------------
    # 5. NETWORK
    # --------------------------------------------------------

    echo ""
    echo "5. Network"

    if [ "$(test_internet)" = "OK" ]; then
        print_ok "Internet connectivity available"
        ((passed++))
    else
        print_warning "Internet connectivity unavailable"
        ((warnings++))
    fi

    # --------------------------------------------------------
    # 6. DNS
    # --------------------------------------------------------

    echo ""
    echo "6. DNS"

    if [ "$(test_dns)" = "OK" ]; then
        print_ok "DNS resolution working"
        ((passed++))
    else
        print_warning "DNS resolution failed"
        ((warnings++))
    fi

    # --------------------------------------------------------
    # 7. ZOMBIES
    # --------------------------------------------------------

    echo ""
    echo "7. Zombie Processes"

    if show_zombie_processes >/dev/null; then
        print_ok "No zombie processes detected"
        ((passed++))
    else
        print_warning "Zombie processes detected"
        ((warnings++))
    fi

    # --------------------------------------------------------
    # 8. SERVICES
    # --------------------------------------------------------

    echo ""
    echo "8. Services"

    if command_exists systemctl; then

        local failed_services
        failed_services=$(get_failed_service_count)

        if (( failed_services == 0 )); then
            print_ok "No failed services detected"
            ((passed++))
        elif (( failed_services > 0 )); then
            print_warning "$failed_services failed service(s) detected"
            ((warnings++))
        else
            print_info "Unable to determine service status"
        fi

    else
        print_info "systemctl unavailable on this system"
    fi

    # --------------------------------------------------------
    # SUMMARY
    # --------------------------------------------------------

    print_section "DIAGNOSTIC SUMMARY"

    echo "Passed    : $passed"
    echo "Warnings  : $warnings"
    echo "Critical  : $critical"

    echo ""

    if (( critical > 0 )); then
        print_critical "Overall diagnostics: CRITICAL"
    elif (( warnings > 0 )); then
        print_warning "Overall diagnostics: WARNING"
    else
        print_ok "Overall diagnostics: PASSED"
    fi

    log_event \
        "Diagnostics completed: passed=$passed warnings=$warnings critical=$critical"

    pause_screen
}

# ============================================================
# LOG VIEWING
# ============================================================

view_logs()
{
    print_header

    print_section "SYSTEM LOG"

    if [ -s "$SYSTEM_LOG" ]; then
        tail -30 "$SYSTEM_LOG"
    else
        echo "No system logs available."
    fi

    pause_screen
}

view_alerts()
{
    print_header

    print_section "ALERT LOG"

    if [ -s "$ALERT_LOG" ]; then
        tail -30 "$ALERT_LOG"
    else
        echo "No alerts recorded."
    fi

    pause_screen
}

view_history()
{
    print_header

    print_section "MONITORING HISTORY"

    if [ -s "$HISTORY_FILE" ]; then
        tail -30 "$HISTORY_FILE"
    else
        echo "No monitoring history available."
    fi

    pause_screen
}

# ============================================================
# CLEAR LOGS
# ============================================================

clear_logs()
{
    print_header

    print_section "CLEAR LOGS"

    echo "This will clear:"
    echo "  - system.log"
    echo "  - alerts.log"
    echo ""

    read -r -p "Continue? (y/N): " confirmation

    if [[ "$confirmation" =~ ^[Yy]$ ]]; then

        : > "$SYSTEM_LOG"
        : > "$ALERT_LOG"

        log_event "Log files cleared by user."

        print_ok "Logs cleared."

    else
        echo "Operation cancelled."
    fi

    pause_screen
}

# ============================================================
# JSON OUTPUT
# ============================================================

json_escape()
{
    local value="$1"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}

    printf '%s' "$value"
}

json_snapshot()
{
    collect_snapshot

    local timestamp
    local hostname_value
    local os_value
    local kernel_value

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    hostname_value=$(get_hostname)
    os_value=$(get_os)
    kernel_value=$(get_kernel)

    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(json_escape "$timestamp")"
    printf '  "hostname": "%s",\n' "$(json_escape "$hostname_value")"
    printf '  "os": "%s",\n' "$(json_escape "$os_value")"
    printf '  "kernel": "%s",\n' "$(json_escape "$kernel_value")"
    printf '  "cpu_percent": %s,\n' "$CPU_VALUE"
    printf '  "ram_percent": %s,\n' "$RAM_VALUE"
    printf '  "swap_percent": %s,\n' "$SWAP_VALUE"
    printf '  "disk_percent": %s,\n' "$DISK_VALUE"
    printf '  "load_1m": %s,\n' "$LOAD_VALUE"
    printf '  "processes": %s,\n' "$PROCESS_VALUE"
    printf '  "health": "%s"\n' "$HEALTH_VALUE"
    printf '}\n'
}

# ============================================================
# CSV OUTPUT
# ============================================================

csv_snapshot()
{
    collect_snapshot

    echo "timestamp,cpu_percent,ram_percent,swap_percent,disk_percent,load_1m,processes,health"

    echo "$(date '+%Y-%m-%d %H:%M:%S'),$CPU_VALUE,$RAM_VALUE,$SWAP_VALUE,$DISK_VALUE,$LOAD_VALUE,$PROCESS_VALUE,$HEALTH_VALUE"
}

# ============================================================
# REPORT GENERATION
# ============================================================

generate_report()
{
    collect_snapshot

    local timestamp
    local report_file

    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    report_file="$REPORT_DIR/health_report_$timestamp.txt"

    {
        echo "======================================================================"
        echo "             LINUX SYSTEM HEALTH & DIAGNOSTICS REPORT"
        echo "======================================================================"
        echo ""
        echo "Generated : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Version   : $VERSION"
        echo ""

        echo "SYSTEM INFORMATION"
        echo "----------------------------------------------------------------------"
        echo "Hostname          : $(get_hostname)"
        echo "Operating System  : $(get_os)"
        echo "Kernel            : $(get_kernel)"
        echo "Architecture      : $(get_architecture)"
        echo "CPU Model         : $(get_cpu_model)"
        echo "CPU Cores         : $(get_cpu_cores)"
        echo "Uptime            : $(get_uptime)"
        echo "Load Average      : $(get_load_average)"
        echo "Current User      : $(get_current_user)"
        echo "Logged-in Users   : $(get_logged_users)"
        echo "Running Processes : $PROCESS_VALUE"
        echo ""

        echo "RESOURCE USAGE"
        echo "----------------------------------------------------------------------"
        echo "CPU Usage         : $CPU_VALUE%"
        echo "RAM Usage         : $RAM_VALUE%"
        echo "Swap Usage        : $SWAP_VALUE%"
        echo "Root Disk         : $DISK_VALUE%"
        echo "Load 1m           : $LOAD_VALUE"
        echo ""

        echo "HEALTH"
        echo "----------------------------------------------------------------------"
        echo "Overall Status    : $HEALTH_VALUE"
        echo ""

        echo "HEALTH ANALYSIS"
        echo "----------------------------------------------------------------------"

        show_health_reasons \
            "$CPU_VALUE" \
            "$RAM_VALUE" \
            "$SWAP_VALUE" \
            "$DISK_VALUE" \
            "$LOAD_VALUE"

        echo ""
        echo "MEMORY"
        echo "----------------------------------------------------------------------"

        free -h 2>/dev/null

        echo ""
        echo "FILESYSTEMS"
        echo "----------------------------------------------------------------------"

        df -h 2>/dev/null

        echo ""
        echo "TOP CPU PROCESSES"
        echo "----------------------------------------------------------------------"

        show_top_cpu_processes

        echo ""
        echo "NETWORK"
        echo "----------------------------------------------------------------------"

        get_ip_addresses

        echo ""
        echo "Default Gateway:"
        get_default_gateway

        echo ""
        echo "DNS:"
        get_dns_servers

        echo ""
        echo "LISTENING PORTS"
        echo "----------------------------------------------------------------------"

        show_listening_ports

        echo ""
        echo "SERVICE STATUS"
        echo "----------------------------------------------------------------------"

        if command_exists systemctl; then
            systemctl --failed --no-pager 2>/dev/null || true
        else
            echo "systemctl unavailable."
        fi

        echo ""
        echo "BASIC SECURITY INFORMATION"
        echo "----------------------------------------------------------------------"

        echo "Current User:"
        id 2>/dev/null || true

        echo ""
        echo "Listening Ports:"
        show_listening_ports

        echo ""
        echo "======================================================================"
        echo "                         END OF REPORT"
        echo "======================================================================"

    } > "$report_file"

    log_event "Generated report: $report_file"

    echo ""
    print_ok "Report generated successfully."
    echo "File: $report_file"

    pause_screen
}

# ============================================================
# LIVE MONITOR
# ============================================================

live_monitor()
{
    local interval="${1:-$REFRESH_INTERVAL}"

    if ! is_integer "$interval" || (( interval < 1 )); then
        echo "Invalid refresh interval."
        return 1
    fi

    if [ -e "$LOCK_FILE" ]; then
        local existing_pid

        existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)

        if [ -n "$existing_pid" ] &&
            kill -0 "$existing_pid" 2>/dev/null
        then
            echo "Another monitor instance is already running."
            return 1
        else
            rm -f "$LOCK_FILE" 2>/dev/null || true
        fi
    fi

    echo "$$" > "$LOCK_FILE"

    while true
    do
        clear

        collect_snapshot

        echo -e "${CYAN}${BOLD}"
        echo "======================================================================"
        echo "                       LIVE SYSTEM MONITOR"
        echo "======================================================================"
        echo -e "${RESET}"

        echo "Time       : $(date '+%H:%M:%S')"
        echo "Hostname   : $(get_hostname)"
        echo "Uptime     : $(get_uptime)"
        echo "Load       : $(get_load_average)"

        echo ""
        echo "RESOURCE USAGE"
        echo "----------------------------------------------------------------------"

        printf "%-18s : %s%%\n" "CPU" "$CPU_VALUE"
        printf "%-18s : %s%%\n" "RAM" "$RAM_VALUE"
        printf "%-18s : %s%%\n" "SWAP" "$SWAP_VALUE"
        printf "%-18s : %s%%\n" "ROOT DISK" "$DISK_VALUE"
        printf "%-18s : %s\n" "LOAD 1m" "$LOAD_VALUE"
        printf "%-18s : %s\n" "PROCESSES" "$PROCESS_VALUE"

        echo ""
        echo "HEALTH"
        echo "----------------------------------------------------------------------"

        case "$HEALTH_VALUE" in
            HEALTHY)
                print_ok "HEALTHY"
                ;;
            WARNING)
                print_warning "WARNING"
                ;;
            CRITICAL)
                print_critical "CRITICAL"
                ;;
        esac

        echo ""
        echo "TOP CPU PROCESSES"
        echo "----------------------------------------------------------------------"

        ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null |
            head -8

        echo ""
        echo "NETWORK"
        echo "----------------------------------------------------------------------"

        if [ "$(test_internet)" = "OK" ]; then
            print_ok "Internet CONNECTED"
        else
            print_warning "Internet OFFLINE"
        fi

        echo ""
        echo "Refreshing every $interval seconds."
        echo "Press Ctrl+C to stop."

        sleep "$interval"
    done
}

# ============================================================
# ONE-SHOT CHECK
# ============================================================

single_check()
{
    collect_snapshot

    local internet_status
    internet_status=$(test_internet)

    echo "Timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Hostname  : $(get_hostname)"
    echo "CPU       : $CPU_VALUE%"
    echo "RAM       : $RAM_VALUE%"
    echo "Swap      : $SWAP_VALUE%"
    echo "Disk      : $DISK_VALUE%"
    echo "Load      : $LOAD_VALUE"
    echo "Processes : $PROCESS_VALUE"
    echo "Internet  : $internet_status"
    echo "Health    : $HEALTH_VALUE"

    save_snapshot

    case "$HEALTH_VALUE" in
        HEALTHY)
            return 0
            ;;
        WARNING)
            return 1
            ;;
        CRITICAL)
            return 2
            ;;
    esac
}

# ============================================================
# HELP
# ============================================================

show_help()
{
    echo ""
    echo "Linux System Health & Diagnostics Monitor v$VERSION"
    echo ""
    echo "Usage:"
    echo "  ./monitor.sh [OPTION]"
    echo ""
    echo "MONITORING"
    echo "  --status            System overview"
    echo "  --cpu               CPU information"
    echo "  --memory            Memory information"
    echo "  --disk              Disk information"
    echo "  --io                Disk I/O"
    echo "  --processes         Process analysis"
    echo ""
    echo "PROCESS"
    echo "  --process-search N  Search process"
    echo ""
    echo "NETWORK"
    echo "  --network           Network information"
    echo "  --ports             Listening ports"
    echo "  --connections       Active connections"
    echo "  --internet          Network diagnostics"
    echo ""
    echo "SYSTEM"
    echo "  --services          Service monitoring"
    echo "  --users             User information"
    echo "  --security          Basic security audit"
    echo "  --diagnostics       Full diagnostics"
    echo ""
    echo "HEALTH"
    echo "  --health            Health analysis"
    echo "  --check             One-shot health check"
    echo ""
    echo "DATA"
    echo "  --logs              View system logs"
    echo "  --alerts            View alerts"
    echo "  --history           View CSV history"
    echo "  --report            Generate report"
    echo "  --json              JSON snapshot"
    echo "  --csv               CSV snapshot"
    echo ""
    echo "LIVE"
    echo "  --live              Live monitoring"
    echo "  --watch N           Live monitoring every N seconds"
    echo ""
    echo "OTHER"
    echo "  --version           Show version"
    echo "  --help              Show help"
    echo ""
}

# ============================================================
# VERSION
# ============================================================

show_version()
{
    echo "Linux System Health & Diagnostics Monitor v$VERSION"
}

# ============================================================
# COMMAND-LINE HANDLER
# ============================================================

handle_arguments()
{
    local option="${1:-}"

    case "$option" in

        "")
            main_menu
            ;;

        --status)
            system_overview
            ;;

        --cpu)
            cpu_monitor
            ;;

        --memory)
            memory_monitor
            ;;

        --disk)
            disk_monitor
            ;;

        --io)
            disk_io_monitor
            ;;

        --processes)
            process_monitor
            ;;

        --process-search)
            if [ -z "${2:-}" ]; then
                echo "Usage: ./monitor.sh --process-search NAME"
                return 1
            fi

            ps -eo pid,ppid,user,state,comm,%cpu,%mem,args 2>/dev/null |
                awk -v search="$2" '
                NR==1 || index(tolower($0),tolower(search)) > 0
                '
            ;;

        --network)
            network_information
            ;;

        --ports)
            show_listening_ports
            ;;

        --connections)
            show_connections
            ;;

        --internet)
            network_diagnostics
            ;;

        --services)
            service_monitor
            ;;

        --users)
            user_information
            ;;

        --security)
            security_audit
            ;;

        --diagnostics)
            full_diagnostics
            ;;

        --health)
            health_analysis
            ;;

        --logs)
            view_logs
            ;;

        --alerts)
            view_alerts
            ;;

        --history)
            view_history
            ;;

        --report)
            generate_report
            ;;

        --json)
            json_snapshot
            ;;

        --csv)
            csv_snapshot
            ;;

        --check)
            single_check
            ;;

        --live)
            live_monitor "$REFRESH_INTERVAL"
            ;;

        --watch)
            if [ -z "${2:-}" ]; then
                echo "Usage: ./monitor.sh --watch SECONDS"
                return 1
            fi

            live_monitor "$2"
            ;;

        --version)
            show_version
            ;;

        --help|-h)
            show_help
            ;;

        *)
            echo "Unknown option: $option"
            echo ""
            show_help
            return 1
            ;;

    esac
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu()
{
    while true
    do
        print_header

        echo "  1.  System Overview"
        echo "  2.  CPU Monitor"
        echo "  3.  Memory Monitor"
        echo "  4.  Disk Monitor"
        echo "  5.  Disk I/O"
        echo "  6.  Process Monitor"
        echo "  7.  Search Process"
        echo "  8.  Process Control"
        echo "  9.  Network Diagnostics"
        echo "  10. Network Connections"
        echo "  11. Internet Test"
        echo "  12. Service Monitor"
        echo "  13. User Information"
        echo "  14. Security Audit"
        echo "  15. Health Analysis"
        echo "  16. Full Diagnostics"
        echo "  17. Live Monitor"
        echo "  18. View Logs"
        echo "  19. View Alerts"
        echo "  20. View History"
        echo "  21. Generate Report"
        echo "  22. JSON Snapshot"
        echo "  23. Clear Logs"
        echo "  24. Help"
        echo "  25. Exit"

        echo ""
        echo "======================================================================"

        read -r -p "Enter your choice: " choice

        case "$choice" in

            1)
                system_overview
                ;;

            2)
                cpu_monitor
                ;;

            3)
                memory_monitor
                ;;

            4)
                disk_monitor
                ;;

            5)
                disk_io_monitor
                ;;

            6)
                process_monitor
                ;;

            7)
                search_process
                ;;

            8)
                process_control
                ;;

            9)
                network_diagnostics
                ;;

            10)
                print_header
                print_section "NETWORK CONNECTIONS"
                show_connections
                pause_screen
                ;;

            11)
                network_diagnostics
                ;;

            12)
                service_monitor
                ;;

            13)
                user_information
                ;;

            14)
                security_audit
                ;;

            15)
                health_analysis
                ;;

            16)
                full_diagnostics
                ;;

            17)
                live_monitor "$REFRESH_INTERVAL"
                ;;

            18)
                view_logs
                ;;

            19)
                view_alerts
                ;;

            20)
                view_history
                ;;

            21)
                generate_report
                ;;

            22)
                print_header
                json_snapshot
                pause_screen
                ;;

            23)
                clear_logs
                ;;

            24)
                print_header
                show_help
                pause_screen
                ;;

            25)
                echo ""
                echo "Exiting Linux System Health Monitor..."
                echo ""
                exit 0
                ;;

            *)
                echo ""
                print_warning "Invalid choice. Select 1-25."
                sleep 2
                ;;

        esac
    done
}

# ============================================================
# PROGRAM START
# ============================================================

initialize
load_configuration

if ! check_dependencies
then
    echo ""
    echo "Please install the missing dependencies and run again."
    exit 1
fi

handle_arguments "${1:-}" "${2:-}"

exit $?
