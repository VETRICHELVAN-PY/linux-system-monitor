# 🐧 Linux System Health & Diagnostics Monitor

A Bash-based Linux system monitoring and diagnostics tool that provides real-time visibility into CPU, memory, disk, processes, networking, services, system health, alerts, logs, and historical resource usage.

The project is designed to demonstrate practical Linux administration, Bash scripting, process management, networking, monitoring, logging, and system-level troubleshooting concepts.

---

## 🚀 Features

### 🖥️ System Monitoring

- CPU usage monitoring
- Per-core CPU usage
- RAM usage monitoring
- Swap usage monitoring
- Disk usage monitoring
- Load average monitoring
- Process count
- System uptime
- Hostname
- Operating system information
- Kernel version
- CPU architecture
- CPU model

### ⚙️ Process Monitoring

- Top CPU-consuming processes
- Top memory-consuming processes
- Process tree
- Zombie process detection
- Process search
- Process information using PID
- Safe process signal control

### 🌐 Network Monitoring

- Network interface information
- IP address detection
- Default gateway detection
- DNS server detection
- Routing table
- Active network connections
- Listening ports
- Gateway connectivity test
- DNS resolution test
- Internet connectivity test
- Network latency measurement

### 🔧 Service Monitoring

- systemd status
- Failed service detection
- Active service count
- Inactive service count

### 🩺 Health Diagnostics

The monitor analyzes:

- CPU
- RAM
- Swap
- Disk
- Load average
- Network
- DNS
- Zombie processes
- System services

Health levels:

- `HEALTHY`
- `WARNING`
- `CRITICAL`

### 🚨 Alert System

The application automatically detects resource threshold violations and records:

- Warning conditions
- Critical conditions
- CPU alerts
- RAM alerts
- Swap alerts
- Disk alerts
- Load average alerts

### 📊 Monitoring History

Resource measurements are stored in CSV format:

```text
timestamp,cpu_percent,ram_percent,swap_percent,disk_percent,load_1m,processes,health
