#!/bin/bash
# =============================================================================
# MySQL Backup Script - MifosBank Production
# =============================================================================
# Schedule: Every 6 hours via cron
# Retention: 30 days
# Encryption: AES-256
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env" 2>/dev/null || true

# Backup settings
BACKUP_DIR="${BACKUP_DIR:-/backups/mysql}"
RETENTION_DAYS="${MYSQL_BACKUP_RETENTION:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mysql_backup_${TIMESTAMP}"

# MySQL containers to backup
MYSQL_CONTAINERS=("infra-mysql" "ph-mysql")
MYSQL_PASSWORD="${MYSQL_PASSWORD}"
PH_MYSQL_PASSWORD="${PH_MYSQL_ROOT_PASSWORD:-$MYSQL_PASSWORD}"

# Encryption key (should be stored securely, e.g., in Vault)
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

log "Starting MySQL backup..."
log "Backup directory: $BACKUP_DIR"

backup_mysql_container() {
    local CONTAINER="$1"
    local PASSWORD="$2"
    local CONTAINER_BACKUP_NAME="${BACKUP_NAME}_${CONTAINER}"

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        warn "MySQL container '$CONTAINER' is not running - skipping"
        return 1
    fi

    log "Backing up container: $CONTAINER"

    # Perform backup using mysqldump
    DUMP_FILE="$BACKUP_DIR/${CONTAINER_BACKUP_NAME}.sql"

    docker exec "$CONTAINER" mysqldump \
        -u root \
        -p"$PASSWORD" \
        --all-databases \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --ssl-mode=REQUIRED \
        2>/dev/null > "$DUMP_FILE"

    if [ ! -s "$DUMP_FILE" ]; then
        rm -f "$DUMP_FILE"
        warn "Backup failed for $CONTAINER - dump file is empty"
        return 1
    fi

    log "Database dump created for $CONTAINER: $(du -h "$DUMP_FILE" | cut -f1)"

    # Compress the backup
    log "Compressing backup for $CONTAINER..."
    gzip -9 "$DUMP_FILE"
    COMPRESSED_FILE="${DUMP_FILE}.gz"

    log "Compressed size: $(du -h "$COMPRESSED_FILE" | cut -f1)"

    # Encrypt the backup if encryption key is provided
    if [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
        log "Encrypting backup with AES-256..."
        ENCRYPTED_FILE="${COMPRESSED_FILE}.enc"

        openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
            -in "$COMPRESSED_FILE" \
            -out "$ENCRYPTED_FILE" \
            -pass env:BACKUP_ENCRYPTION_KEY

        rm -f "$COMPRESSED_FILE"
        FINAL_FILE="$ENCRYPTED_FILE"
    else
        FINAL_FILE="$COMPRESSED_FILE"
    fi

    # Generate checksum for integrity verification
    sha256sum "$FINAL_FILE" > "${FINAL_FILE}.sha256"

    log "Backup complete for $CONTAINER: $FINAL_FILE"
    return 0
}

# Backup each MySQL container
SUCCESS_COUNT=0
TOTAL_COUNT=${#MYSQL_CONTAINERS[@]}

for container in "${MYSQL_CONTAINERS[@]}"; do
    case "$container" in
        "infra-mysql")
            if backup_mysql_container "$container" "$MYSQL_PASSWORD"; then
                ((SUCCESS_COUNT++))
            fi
            ;;
        "ph-mysql")
            if backup_mysql_container "$container" "$PH_MYSQL_PASSWORD"; then
                ((SUCCESS_COUNT++))
            fi
            ;;
    esac
done

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "mysql_backup_*.sql.gz*" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "mysql_backup_*.sha256" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# Summary
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/mysql_backup_*.sql.gz* 2>/dev/null | wc -l | tr -d ' ')

log "=========================================="
log "MySQL Backup Complete"
log "=========================================="
log "Containers backed up: $SUCCESS_COUNT/$TOTAL_COUNT"
log "Total backups retained: $BACKUP_COUNT"
if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
    log "WARNING: Backups are NOT encrypted"
fi
log "=========================================="

# Exit with appropriate code
if [ "$SUCCESS_COUNT" -eq 0 ]; then
    exit 1
elif [ "$SUCCESS_COUNT" -lt "$TOTAL_COUNT" ]; then
    exit 2  # Partial success
else
    exit 0
fi
