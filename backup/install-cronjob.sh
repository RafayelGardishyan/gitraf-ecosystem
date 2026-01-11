#!/bin/bash
# Install cronjob for gitraf S3 backup
# Runs backup every midnight

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/s3-backup.sh"
CRON_FILE="/etc/cron.d/gitraf-backup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_backup_script() {
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        log_error "Backup script not found: $BACKUP_SCRIPT"
        exit 1
    fi

    if [[ ! -x "$BACKUP_SCRIPT" ]]; then
        log_info "Making backup script executable"
        chmod +x "$BACKUP_SCRIPT"
    fi
}

check_config() {
    local config_file="${SCRIPT_DIR}/backup.conf"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        log_error "Copy backup.conf.example to backup.conf and configure it"
        exit 1
    fi

    source "$config_file"

    if [[ -z "${S3_BUCKET:-}" ]] || [[ "$S3_BUCKET" == "your-bucket-name" ]]; then
        log_error "S3_BUCKET not configured in $config_file"
        exit 1
    fi

    log_info "Configuration validated"
}

install_cronjob() {
    log_info "Installing cronjob for midnight backup..."

    cat > "$CRON_FILE" << EOF
# gitraf S3 Backup - Runs every midnight
# Installed by install-cronjob.sh

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Run backup at midnight every day
0 0 * * * root ${BACKUP_SCRIPT} >> /var/log/gitraf-backup/cron.log 2>&1
EOF

    chmod 644 "$CRON_FILE"
    log_info "Cronjob installed: $CRON_FILE"
}

install_systemd_timer() {
    log_info "Installing systemd timer as alternative..."

    cat > /etc/systemd/system/gitraf-backup.service << EOF
[Unit]
Description=gitraf S3 Repository Backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT}
User=root
StandardOutput=append:/var/log/gitraf-backup/backup.log
StandardError=append:/var/log/gitraf-backup/backup.log

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/gitraf-backup.timer << EOF
[Unit]
Description=Run gitraf S3 backup daily at midnight

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    log_info "Systemd timer created (not enabled - using cron by default)"
    log_info "To use systemd instead of cron:"
    log_info "  sudo rm $CRON_FILE"
    log_info "  sudo systemctl enable --now gitraf-backup.timer"
}

create_log_dir() {
    mkdir -p /var/log/gitraf-backup
    chmod 755 /var/log/gitraf-backup
    log_info "Log directory created: /var/log/gitraf-backup"
}

verify_installation() {
    log_info "Verifying installation..."

    if [[ -f "$CRON_FILE" ]]; then
        log_info "Cron file installed: $CRON_FILE"
    fi

    if command -v aws &> /dev/null; then
        log_info "AWS CLI installed"
    else
        log_warn "AWS CLI not found - install with: sudo apt install awscli"
    fi

    log_info ""
    log_info "Installation complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Configure AWS credentials: aws configure"
    log_info "  2. Edit backup.conf with your S3 bucket"
    log_info "  3. Test with: sudo ${BACKUP_SCRIPT} --dry-run"
    log_info "  4. Run manually: sudo ${BACKUP_SCRIPT}"
    log_info ""
    log_info "Backup schedule: Every day at midnight (00:00)"
    log_info "Logs: /var/log/gitraf-backup/"
}

uninstall() {
    log_info "Uninstalling gitraf backup cronjob..."

    if [[ -f "$CRON_FILE" ]]; then
        rm -f "$CRON_FILE"
        log_info "Removed: $CRON_FILE"
    fi

    if [[ -f /etc/systemd/system/gitraf-backup.timer ]]; then
        systemctl disable --now gitraf-backup.timer 2>/dev/null || true
        rm -f /etc/systemd/system/gitraf-backup.timer
        rm -f /etc/systemd/system/gitraf-backup.service
        systemctl daemon-reload
        log_info "Removed systemd timer and service"
    fi

    log_info "Uninstall complete"
}

show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install     Install cronjob for midnight backup (default)"
    echo "  uninstall   Remove cronjob and systemd timer"
    echo "  status      Show current backup schedule status"
    echo "  help        Show this help message"
}

show_status() {
    echo "gitraf Backup Status"
    echo "===================="

    if [[ -f "$CRON_FILE" ]]; then
        echo "Cron job: INSTALLED"
        echo "  File: $CRON_FILE"
        echo "  Schedule: Daily at midnight"
    else
        echo "Cron job: NOT INSTALLED"
    fi

    echo ""

    if systemctl is-enabled gitraf-backup.timer &>/dev/null; then
        echo "Systemd timer: ENABLED"
        systemctl status gitraf-backup.timer --no-pager 2>/dev/null || true
    else
        echo "Systemd timer: NOT ENABLED"
    fi

    echo ""

    if [[ -d /var/log/gitraf-backup ]]; then
        echo "Recent logs:"
        ls -lt /var/log/gitraf-backup/*.log 2>/dev/null | head -5 || echo "  No logs found"
    fi
}

# Main
case "${1:-install}" in
    install)
        check_root
        check_backup_script
        check_config
        create_log_dir
        install_cronjob
        install_systemd_timer
        verify_installation
        ;;
    uninstall)
        check_root
        uninstall
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
