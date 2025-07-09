#!/bin/bash

DEBUG=false
if [ "$DEBUG" = true ]; then
    set -x
fi

echo "System Health Monitor: Monitors CPU, memory, disk, network usage, updates, and sends email alerts"

# Thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=80

# Log files
LOG_FILE="/var/log/system_health.log"
ALERT_LOG="/var/log/system_alerts.log"

# Update configuration
CHECK_UPDATES=true
AUTO_INSTALL_UPDATES=false
UPDATE_ALERT_THRESHOLD=10
AUTO_REBOOT=false
REBOOT_DELAY_MINUTES=5

# Check required SMTP environment variables
if [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASS" ] || [ -z "$EMAIL_RECIPIENT" ]; then
    echo "Missing SMTP credentials or recipient email. Please export SMTP_USER, SMTP_PASS, and EMAIL_RECIPIENT."
    exit 1
fi

# Ensure log files are writable
for FILE in "$LOG_FILE" "$ALERT_LOG"; do
    if ! touch "$FILE" &>/dev/null; then
        echo "ERROR: Cannot write to $FILE. Use sudo or check permissions."
        exit 1
    fi
    chmod 600 "$FILE"
done

echo "[$(date "+%Y-%m-%d %H:%M:%S")] System Health Check Started" >> "$LOG_FILE"

check_cpu() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    echo "[$TIMESTAMP] CPU Usage: $CPU_USAGE%" >> "$LOG_FILE"
    echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l | grep -q 1 && {
        echo "[$TIMESTAMP] ALERT: CPU usage is high: $CPU_USAGE%" >> "$LOG_FILE"
        return 1
    }
    return 0
}

check_memory() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    MEMORY_USAGE=$(free | awk '/Mem:/ {printf("%.2f", $3/$2 * 100.0)}')
    echo "[$TIMESTAMP] Memory Usage: $MEMORY_USAGE%" >> "$LOG_FILE"
    echo "$MEMORY_USAGE > $MEMORY_THRESHOLD" | bc -l | grep -q 1 && {
        echo "[$TIMESTAMP] ALERT: Memory usage is high: $MEMORY_USAGE%" >> "$LOG_FILE"
        return 1
    }
    return 0
}

check_disk() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    echo "[$TIMESTAMP] Disk Usage: $DISK_USAGE%" >> "$LOG_FILE"
    [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ] && {
        echo "[$TIMESTAMP] ALERT: Disk usage is high: $DISK_USAGE%" >> "$LOG_FILE"
        return 1
    }
    return 0
}

check_network() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    PACKET_LOSS=$(ping -c 4 8.8.8.8 | grep -oP '\\d+(?=% packet loss)')
    echo "[$TIMESTAMP] Network Packet Loss: $PACKET_LOSS%" >> "$LOG_FILE"
    [ "$PACKET_LOSS" -gt 50 ] && {
        echo "[$TIMESTAMP] ALERT: High packet loss detected: $PACKET_LOSS%" >> "$LOG_FILE"
        return 1
    }
    return 0
}

check_updates() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] Checking for system updates..." >> "$LOG_FILE"

    if command -v apt &>/dev/null; then
        sudo apt update &>/dev/null
        UPDATES_AVAILABLE=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
        PACKAGE_MANAGER="apt"
        UPDATE_COMMAND="sudo apt upgrade -y"
    elif command -v dnf &>/dev/null; then
        UPDATES_AVAILABLE=$(sudo dnf check-update -q | grep -v "^$" | wc -l)
        PACKAGE_MANAGER="dnf"
        UPDATE_COMMAND="sudo dnf upgrade -y"
    elif command -v yum &>/dev/null; then
        UPDATES_AVAILABLE=$(sudo yum check-update -q | grep -v "^$" | wc -l)
        PACKAGE_MANAGER="yum"
        UPDATE_COMMAND="sudo yum update -y"
    else
        echo "[$TIMESTAMP] ERROR: Unsupported package manager" >> "$LOG_FILE"
        return 2
    fi

    echo "[$TIMESTAMP] Found $UPDATES_AVAILABLE updates via $PACKAGE_MANAGER" >> "$LOG_FILE"
    [ "$UPDATES_AVAILABLE" -gt 0 ] && return 1 || return 0
}

install_updates() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] Installing system updates..." >> "$LOG_FILE"
    local UPDATE_LOG="/var/log/system_updates_$(date +%Y%m%d_%H%M%S).log"
    $UPDATE_COMMAND &> "$UPDATE_LOG"
    local STATUS=$?
    [ $STATUS -eq 0 ] && echo "[$TIMESTAMP] Updates installed successfully" >> "$LOG_FILE" || {
        echo "[$TIMESTAMP] ERROR: Update failed with status $STATUS" >> "$LOG_FILE"
        return 1
    }
    return 0
}

send_alert() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    local SUBJECT="ALERT: System Health Issue on $(hostname)"
    local BODY="System Alert on $(hostname) at $TIMESTAMP:\n\n$1"

    if ! command -v sendemail &>/dev/null; then
        echo "[$TIMESTAMP] WARNING: 'sendemail' not found, alert not sent." >> "$ALERT_LOG"
        echo -e "$BODY" >> "$ALERT_LOG"
        return 1
    fi

    sendemail -f "$SMTP_USER" \
              -t "$EMAIL_RECIPIENT" \
              -u "$SUBJECT" \
              -m "$BODY" \
              -s smtp.gmail.com:587 \
              -o tls=yes \
              -xu "$SMTP_USER" \
              -xp "$SMTP_PASS"

    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] Alert sent to $EMAIL_RECIPIENT" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] ERROR: Failed to send alert" >> "$ALERT_LOG"
    fi
}

# ----------------- MAIN ------------------

ALERT_MESSAGE=""

check_cpu; [ $? -eq 1 ] && ALERT_MESSAGE+="- High CPU usage\n"
check_memory; [ $? -eq 1 ] && ALERT_MESSAGE+="- High memory usage\n"
check_disk; [ $? -eq 1 ] && ALERT_MESSAGE+="- High disk usage\n"
check_network; [ $? -eq 1 ] && ALERT_MESSAGE+="- High network packet loss\n"

if [ "$CHECK_UPDATES" = true ]; then
    check_updates
    [ $? -eq 1 ] && ALERT_MESSAGE+="- System updates available\n"
    if [ "$AUTO_INSTALL_UPDATES" = true ]; then
        install_updates || ALERT_MESSAGE+="- Failed to install updates\n"
    fi
fi

if [ -n "$ALERT_MESSAGE" ]; then
    send_alert "$ALERT_MESSAGE"
    echo -e "$ALERT_MESSAGE"
fi

echo "[$(date "+%Y-%m-%d %H:%M:%S")] System Health Check Completed" >> "$LOG_FILE"
