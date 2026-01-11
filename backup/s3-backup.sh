#!/bin/bash
# S3 Backup Script for gitraf repositories
# Syncs all git repositories to S3 storage at midnight

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"
LOG_DIR="/var/log/gitraf-backup"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m%d).log"
LOCK_FILE="/var/run/gitraf-backup.lock"

# Default values (can be overridden by config file)
REPOS_DIR="${REPOS_DIR:-/var/lib/gitraf/repos}"
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-gitraf-backup}"
AWS_PROFILE="${AWS_PROFILE:-default}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESSION="${COMPRESSION:-true}"

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Check dependencies
check_dependencies() {
    local missing=()

    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi

    if [[ "$COMPRESSION" == "true" ]] && ! command -v tar &> /dev/null; then
        missing+=("tar")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing[*]}"
        log "ERROR" "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi
}

# Validate configuration
validate_config() {
    if [[ -z "$S3_BUCKET" ]]; then
        log "ERROR" "S3_BUCKET not configured. Set in $CONFIG_FILE"
        exit 1
    fi

    if [[ ! -d "$REPOS_DIR" ]]; then
        log "ERROR" "Repository directory not found: $REPOS_DIR"
        exit 1
    fi
}

# Acquire lock to prevent concurrent runs
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            log "ERROR" "Backup already running (PID: $pid)"
            exit 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT
}

# Backup a single repository
backup_repo() {
    local repo_path="$1"
    local repo_name=$(basename "$repo_path")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="${repo_name}_${timestamp}"
    local temp_dir=$(mktemp -d)

    log "INFO" "Backing up repository: $repo_name"

    if [[ "$COMPRESSION" == "true" ]]; then
        local archive="${temp_dir}/${backup_name}.tar.gz"
        tar -czf "$archive" -C "$(dirname "$repo_path")" "$repo_name"

        aws s3 cp "$archive" "s3://${S3_BUCKET}/${S3_PREFIX}/${repo_name}/${backup_name}.tar.gz" \
            --profile "$AWS_PROFILE" \
            --quiet
    else
        aws s3 sync "$repo_path" "s3://${S3_BUCKET}/${S3_PREFIX}/${repo_name}/latest/" \
            --profile "$AWS_PROFILE" \
            --delete \
            --quiet
    fi

    rm -rf "$temp_dir"
    log "INFO" "Completed backup: $repo_name"
}

# Sync all repositories
sync_repositories() {
    local count=0
    local failed=0

    log "INFO" "Starting repository sync from: $REPOS_DIR"

    for repo in "$REPOS_DIR"/*.git; do
        if [[ -d "$repo" ]]; then
            if backup_repo "$repo"; then
                ((count++))
            else
                ((failed++))
                log "ERROR" "Failed to backup: $(basename "$repo")"
            fi
        fi
    done

    # Also backup bare repos without .git extension
    for repo in "$REPOS_DIR"/*/; do
        if [[ -d "${repo}objects" ]] && [[ -d "${repo}refs" ]]; then
            if backup_repo "${repo%/}"; then
                ((count++))
            else
                ((failed++))
                log "ERROR" "Failed to backup: $(basename "${repo%/}")"
            fi
        fi
    done

    log "INFO" "Sync completed. Backed up: $count, Failed: $failed"
    return $failed
}

# Cleanup old backups based on retention policy
cleanup_old_backups() {
    if [[ "$RETENTION_DAYS" -le 0 ]]; then
        log "INFO" "Retention disabled, skipping cleanup"
        return
    fi

    log "INFO" "Cleaning up backups older than $RETENTION_DAYS days"

    local cutoff_date=$(date -d "-${RETENTION_DAYS} days" +%Y%m%d 2>/dev/null || \
                        date -v-${RETENTION_DAYS}d +%Y%m%d)

    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive --profile "$AWS_PROFILE" | \
    while read -r line; do
        local file_date=$(echo "$line" | awk '{print $1}' | tr -d '-')
        local file_path=$(echo "$line" | awk '{print $4}')

        if [[ "$file_date" < "$cutoff_date" ]] && [[ -n "$file_path" ]]; then
            log "INFO" "Deleting old backup: $file_path"
            aws s3 rm "s3://${S3_BUCKET}/${file_path}" --profile "$AWS_PROFILE" --quiet
        fi
    done
}

# Main function
main() {
    mkdir -p "$LOG_DIR"

    log "INFO" "========================================="
    log "INFO" "gitraf S3 Backup starting"
    log "INFO" "========================================="

    load_config
    check_dependencies
    validate_config
    acquire_lock

    local start_time=$(date +%s)

    if sync_repositories; then
        cleanup_old_backups
        log "INFO" "Backup completed successfully"
    else
        log "WARN" "Backup completed with some failures"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log "INFO" "Total duration: ${duration} seconds"
    log "INFO" "========================================="
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Show what would be backed up without doing it"
        echo "  --list         List all repositories that would be backed up"
        echo ""
        echo "Configuration: $CONFIG_FILE"
        exit 0
        ;;
    --dry-run)
        log "INFO" "DRY RUN - No changes will be made"
        load_config
        validate_config
        echo "Would backup repositories from: $REPOS_DIR"
        echo "To S3 bucket: s3://${S3_BUCKET}/${S3_PREFIX}/"
        exit 0
        ;;
    --list)
        load_config
        echo "Repositories to backup:"
        for repo in "${REPOS_DIR}"/*.git "${REPOS_DIR}"/*/; do
            if [[ -d "$repo" ]]; then
                echo "  - $(basename "${repo%/}")"
            fi
        done
        exit 0
        ;;
    *)
        main
        ;;
esac
