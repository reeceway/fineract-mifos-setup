#!/bin/bash
# =============================================================================
# Master Backup Script - MifosBank Production
# =============================================================================
# Runs all backup scripts and generates summary report
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment
source "$PROJECT_ROOT/.env" 2>/dev/null || true

# Backup directories
BACKUP_BASE="${BACKUP_DIR:-/backups}"
LOG_DIR="$BACKUP_BASE/logs"
mkdir -p "$LOG_DIR"

# Log file for this run
LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"

# Logging
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# Track results
declare -A RESULTS

run_backup() {
    local name="$1"
    local script="$2"

    log "=========================================="
    log "Starting backup: $name"
    log "=========================================="

    if [ -x "$script" ]; then
        if "$script" >> "$LOG_FILE" 2>&1; then
            RESULTS[$name]="SUCCESS"
            log "$name backup: SUCCESS"
        else
            RESULTS[$name]="FAILED"
            log "$name backup: FAILED"
        fi
    else
        RESULTS[$name]="SKIPPED (script not found)"
        log "$name backup: SKIPPED (script not found)"
    fi
}

# Start backup run
log "=========================================="
log "MifosBank Backup Run Started"
log "=========================================="
log "Timestamp: $(date)"
log "Backup directory: $BACKUP_BASE"
log ""

# Run all backups
run_backup "PostgreSQL" "$SCRIPT_DIR/backup-postgres.sh"
run_backup "MySQL" "$SCRIPT_DIR/backup-mysql.sh"
run_backup "Elasticsearch" "$SCRIPT_DIR/backup-elasticsearch.sh"
run_backup "Vault" "$SCRIPT_DIR/backup-vault.sh"

# Summary
log ""
log "=========================================="
log "BACKUP SUMMARY"
log "=========================================="
SUCCESS_COUNT=0
FAILED_COUNT=0

for name in "${!RESULTS[@]}"; do
    log "$name: ${RESULTS[$name]}"
    if [ "${RESULTS[$name]}" == "SUCCESS" ]; then
        ((SUCCESS_COUNT++))
    elif [ "${RESULTS[$name]}" == "FAILED" ]; then
        ((FAILED_COUNT++))
    fi
done

log ""
log "Total: ${#RESULTS[@]} | Success: $SUCCESS_COUNT | Failed: $FAILED_COUNT"
log "Log file: $LOG_FILE"
log "=========================================="

# Cleanup old logs (keep 30 days)
find "$LOG_DIR" -name "backup_*.log" -mtime +30 -delete 2>/dev/null || true

# Exit code based on results
if [ "$FAILED_COUNT" -gt 0 ]; then
    exit 1
else
    exit 0
fi
