#!/bin/bash
# =============================================================================
# PostgreSQL Restore Script - MifosBank Production
# =============================================================================
# Usage: ./restore-postgres.sh [backup_file]
# If no backup file specified, uses the most recent backup
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env" 2>/dev/null || true

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}/postgres"
PG_CONTAINER="${PG_CONTAINER:-mifosx-postgresql-postgresql-1}"
PG_USER="${POSTGRES_USER:-postgres}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

# Determine backup file to restore
if [ $# -ge 1 ]; then
    BACKUP_FILE="$1"
else
    # Find the most recent backup
    log "No backup file specified, finding most recent..."
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/postgres_backup_*.sql.gz* 2>/dev/null | head -1)

    if [ -z "$BACKUP_FILE" ]; then
        error "No backup files found in $BACKUP_DIR"
    fi
fi

if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
fi

log "=========================================="
log "PostgreSQL Restore"
log "=========================================="
log "Backup file: $BACKUP_FILE"
log "Target container: $PG_CONTAINER"
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
if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    error "PostgreSQL container '$PG_CONTAINER' is not running"
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
echo "WARNING: This will restore the PostgreSQL database from backup."
echo "All current data will be replaced."
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log "Restore cancelled by user"
    exit 0
fi

# Perform restore
log "Starting restore..."

# Copy SQL file to container
docker cp "$SQL_FILE" "$PG_CONTAINER:/tmp/restore.sql"

# Execute restore
docker exec "$PG_CONTAINER" psql -U "$PG_USER" -f /tmp/restore.sql > /dev/null 2>&1

# Cleanup
docker exec "$PG_CONTAINER" rm -f /tmp/restore.sql

log "=========================================="
log "PostgreSQL Restore Complete"
log "=========================================="
log "Database restored from: $BACKUP_FILE"
log "Please verify your application is working correctly."
log "=========================================="

exit 0
