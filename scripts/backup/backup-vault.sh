#!/bin/bash
# =============================================================================
# HashiCorp Vault Backup Script - MifosBank Production
# =============================================================================
# Schedule: Daily via cron
# Retention: 30 days
# Encryption: AES-256
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env" 2>/dev/null || true

# Backup settings
BACKUP_DIR="${BACKUP_DIR:-/backups/vault}"
RETENTION_DAYS="${VAULT_BACKUP_RETENTION:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vault_backup_${TIMESTAMP}"

# Vault settings
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8210}"
VAULT_TOKEN="${VAULT_DEV_ROOT_TOKEN_ID}"
VAULT_CONTAINER="${VAULT_CONTAINER:-mifos-vault}"

# Encryption key (should be stored securely)
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Starting Vault backup..."
log "Vault address: $VAULT_ADDR"
log "Backup directory: $BACKUP_DIR"

# Check Vault is accessible
VAULT_HEALTH=$(curl -s "$VAULT_ADDR/v1/sys/health" 2>/dev/null)
if [ -z "$VAULT_HEALTH" ]; then
    error "Cannot connect to Vault at $VAULT_ADDR"
fi

VAULT_SEALED=$(echo "$VAULT_HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sealed', True))")
if [ "$VAULT_SEALED" == "True" ]; then
    error "Vault is sealed - cannot perform backup"
fi

log "Vault is unsealed and accessible"

# Create backup directory for this backup
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
mkdir -p "$BACKUP_PATH"

# Export all secrets from KV mounts
log "Exporting secrets from KV mounts..."

# List all mounts
MOUNTS=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/mounts" 2>/dev/null)

# Export KV secrets
export_kv_secrets() {
    local mount_path="$1"
    local output_file="$BACKUP_PATH/${mount_path//\//_}secrets.json"

    log "Exporting secrets from: $mount_path"

    # List all keys in the mount
    KEYS=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/${mount_path}metadata?list=true" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d.get('data',{}).get('keys',[])))" 2>/dev/null || echo "")

    if [ -z "$KEYS" ]; then
        warn "No keys found in $mount_path or failed to list"
        return
    fi

    # Create JSON structure for secrets
    echo "{" > "$output_file"
    first=true

    for key in $KEYS; do
        SECRET=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/${mount_path}data/${key}" 2>/dev/null)

        if [ -n "$SECRET" ]; then
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$output_file"
            fi
            echo "\"$key\": $SECRET" >> "$output_file"
        fi
    done

    echo "}" >> "$output_file"
    log "Exported secrets from $mount_path to $output_file"
}

# Export from known KV mounts
for mount in "secret/" "certificates/"; do
    export_kv_secrets "$mount" || true
done

# Export Vault policies
log "Exporting Vault policies..."
POLICIES=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/sys/policies/acl?list=true" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(d.get('data',{}).get('keys',[])))" 2>/dev/null || echo "root default")

for policy in $POLICIES; do
    if [ "$policy" != "root" ] && [ "$policy" != "default" ]; then
        POLICY_DATA=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/sys/policies/acl/$policy" 2>/dev/null)
        echo "$POLICY_DATA" > "$BACKUP_PATH/policy_${policy}.json"
    fi
done

# Export Vault configuration
log "Exporting Vault configuration..."
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/sys/mounts" > "$BACKUP_PATH/mounts.json" 2>/dev/null || true
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/sys/auth" > "$BACKUP_PATH/auth_methods.json" 2>/dev/null || true
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/sys/audit" > "$BACKUP_PATH/audit_devices.json" 2>/dev/null || true

# Create tarball
log "Creating backup archive..."
ARCHIVE_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
tar -czf "$ARCHIVE_FILE" -C "$BACKUP_DIR" "$BACKUP_NAME"
rm -rf "$BACKUP_PATH"

log "Archive created: $(du -h "$ARCHIVE_FILE" | cut -f1)"

# Encrypt the backup if encryption key is provided
if [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
    log "Encrypting backup with AES-256..."
    ENCRYPTED_FILE="${ARCHIVE_FILE}.enc"

    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "$ARCHIVE_FILE" \
        -out "$ENCRYPTED_FILE" \
        -pass env:BACKUP_ENCRYPTION_KEY

    rm -f "$ARCHIVE_FILE"
    FINAL_FILE="$ENCRYPTED_FILE"
    log "Encryption complete"
else
    warn "Backup encryption key not set - backup is NOT encrypted"
    FINAL_FILE="$ARCHIVE_FILE"
fi

# Generate checksum
sha256sum "$FINAL_FILE" > "${FINAL_FILE}.sha256"

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "vault_backup_*.tar.gz*" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "vault_backup_*.sha256" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# Summary
BACKUP_SIZE=$(du -h "$FINAL_FILE" | cut -f1)
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/vault_backup_*.tar.gz* 2>/dev/null | wc -l | tr -d ' ')

log "=========================================="
log "Vault Backup Complete"
log "=========================================="
log "Backup file: $FINAL_FILE"
log "Size: $BACKUP_SIZE"
log "Checksum: ${FINAL_FILE}.sha256"
log "Total backups retained: $BACKUP_COUNT"
log "=========================================="

exit 0
