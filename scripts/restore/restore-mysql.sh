#!/bin/bash
# =============================================================================
# MySQL Restore Script - MifosBank Production
# =============================================================================
# Usage: ./restore-mysql.sh [backup_file] [container_name]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env" 2>/dev/null || true

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}/mysql"
DEFAULT_CONTAINER="infra-mysql"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

# Parse arguments
BACKUP_FILE="${1:-}"
MYSQL_CONTAINER="${2:-$DEFAULT_CONTAINER}"

# Determine MySQL password based on container
case "$MYSQL_CONTAINER" in
    "infra-mysql")
        MYSQL_PASSWORD="${MYSQL_PASSWORD}"
        ;;
    "ph-mysql")
        MYSQL_PASSWORD="${PH_MYSQL_ROOT_PASSWORD:-$MYSQL_PASSWORD}"
        ;;
    *)
        MYSQL_PASSWORD="${MYSQL_PASSWORD}"
        ;;
esac

# Find backup file if not specified
if [ -z "$BACKUP_FILE" ]; then
    log "No backup file specified, finding most recent for $MYSQL_CONTAINER..."
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/mysql_backup_*_${MYSQL_CONTAINER}.sql.gz* 2>/dev/null | head -1)

    if [ -z "$BACKUP_FILE" ]; then
        error "No backup files found for $MYSQL_CONTAINER in $BACKUP_DIR"
    fi
fi

if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
fi

log "=========================================="
log "MySQL Restore"
log "=========================================="
log "Backup file: $BACKUP_FILE"
log "Target container: $MYSQL_CONTAINER"
log ""

# Verify checksum if available
CHECKSUM_FILE="${BACKUP_FILE}.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
    log "Verifying backup integrity..."
    if ! cd "$(dirname "$BACKUP_FILE")" || ! sha256sum -c "$(basename "$CHECKSUM_FILE")" > /dev/null 2>&1; then
        error "Checksum verification failed!"
    fi
    log "Checksum verified ✓"
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    error "MySQL container '$MYSQL_CONTAINER' is not running"
fi

# Create working copy
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

log "Preparing backup for restore..."

# Decrypt if encrypted
if [[ "$BACKUP_FILE" == *.enc ]]; then
    if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        error "Backup is encrypted but BACKUP_ENCRYPTION_KEY is not set"
    fi

    log "Decrypting backup..."
    DECRYPTED_FILE="$WORK_DIR/backup.sql.gz"

    openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -in "$BACKUP_FILE" \
        -out "$DECRYPTED_FILE" \
        -pass env:BACKUP_ENCRYPTION_KEY

    WORK_FILE="$DECRYPTED_FILE"
else
    WORK_FILE="$BACKUP_FILE"
fi

# Decompress
log "Decompressing backup..."
SQL_FILE="$WORK_DIR/backup.sql"
gunzip -c "$WORK_FILE" > "$SQL_FILE"

log "Backup size: $(du -h "$SQL_FILE" | cut -f1)"

# Confirm restore
echo ""
echo "WARNING: This will restore the MySQL database from backup."
echo "All current data in $MYSQL_CONTAINER will be replaced."
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log "Restore cancelled by user"
    exit 0
fi

# Perform restore
log "Starting restore..."

# Copy SQL file to container
docker cp "$SQL_FILE" "$MYSQL_CONTAINER:/tmp/restore.sql"

# Execute restore
docker exec "$MYSQL_CONTAINER" mysql -u root -p"$MYSQL_PASSWORD" \
    --ssl-mode=REQUIRED < /tmp/restore.sql 2>/dev/null || \
docker exec -i "$MYSQL_CONTAINER" mysql -u root -p"$MYSQL_PASSWORD" < "$SQL_FILE" 2>/dev/null

# Cleanup
docker exec "$MYSQL_CONTAINER" rm -f /tmp/restore.sql 2>/dev/null || true

log "=========================================="
log "MySQL Restore Complete"
log "=========================================="
log "Database restored from: $BACKUP_FILE"
log "Container: $MYSQL_CONTAINER"
log "Please verify your application is working correctly."
log "=========================================="

exit 0
