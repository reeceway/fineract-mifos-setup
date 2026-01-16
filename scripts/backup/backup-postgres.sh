#!/bin/bash
# =============================================================================
# PostgreSQL Backup Script - MifosBank Production
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
BACKUP_DIR="${BACKUP_DIR:-/backups/postgres}"
RETENTION_DAYS="${POSTGRES_BACKUP_RETENTION:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="postgres_backup_${TIMESTAMP}"

# PostgreSQL settings
PG_CONTAINER="${PG_CONTAINER:-mifosx-postgresql-postgresql-1}"
PG_USER="${POSTGRES_USER:-postgres}"
PG_PASSWORD="${POSTGRES_PASSWORD}"

# Encryption key (should be stored securely, e.g., in Vault)
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

log "Starting PostgreSQL backup..."
log "Container: $PG_CONTAINER"
log "Backup directory: $BACKUP_DIR"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    error "PostgreSQL container '$PG_CONTAINER' is not running"
fi

# Perform backup using pg_dumpall for complete backup
log "Creating database dump..."
DUMP_FILE="$BACKUP_DIR/${BACKUP_NAME}.sql"

docker exec "$PG_CONTAINER" pg_dumpall -U "$PG_USER" > "$DUMP_FILE" 2>/dev/null

if [ ! -s "$DUMP_FILE" ]; then
    rm -f "$DUMP_FILE"
    error "Backup failed - dump file is empty"
fi

log "Database dump created: $(du -h "$DUMP_FILE" | cut -f1)"

# Compress the backup
log "Compressing backup..."
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
    log "Encryption complete"
else
    log "WARNING: Backup encryption key not set - backup is NOT encrypted"
    FINAL_FILE="$COMPRESSED_FILE"
fi

# Generate checksum for integrity verification
log "Generating checksum..."
sha256sum "$FINAL_FILE" > "${FINAL_FILE}.sha256"

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "postgres_backup_*.sql.gz*" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "postgres_backup_*.sha256" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# Summary
BACKUP_SIZE=$(du -h "$FINAL_FILE" | cut -f1)
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/postgres_backup_*.sql.gz* 2>/dev/null | wc -l | tr -d ' ')

log "=========================================="
log "PostgreSQL Backup Complete"
log "=========================================="
log "Backup file: $FINAL_FILE"
log "Size: $BACKUP_SIZE"
log "Checksum: ${FINAL_FILE}.sha256"
log "Total backups retained: $BACKUP_COUNT"
log "=========================================="

# Exit successfully
exit 0
