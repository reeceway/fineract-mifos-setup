#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${SCRIPT_DIR}/../../backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"
LOG_FILE="${BACKUP_ROOT}/backup.log"

# Services
POSTGRES_CONTAINER="mifosx-postgresql-postgresql-1"
MYSQL_CONTAINER="infra-mysql"
VAULT_CONTAINER="mifos-vault"
VAULT_DATA_DIR="${SCRIPT_DIR}/infrastructure/vault/file"
VAULT_KEYS_DIR="${SCRIPT_DIR}/infrastructure/vault/keys"

# Logging
mkdir -p "$BACKUP_ROOT"
log_info() { echo -e "\033[0;32m[INFO]\033[0m [$(date)] $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m [$(date)] $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m [$(date)] $1" | tee -a "$LOG_FILE"; }

log_info "Starting backup..."
mkdir -p "$BACKUP_DIR"

# 1. Backup PostgreSQL (Fineract Tenants & Default)
log_info "Backing up PostgreSQL..."
if docker exec "$POSTGRES_CONTAINER" pg_dumpall -c -U postgres > "$BACKUP_DIR/postgres_dump.sql"; then
    log_info "PostgreSQL backup successful."
else
    log_error "PostgreSQL backup failed."
    exit 1
fi

# 2. Backup MySQL
log_info "Backing up MySQL..."
# Need password. Try to find it in .env or assume passed via env.
# Better: use defaults-extra-file or similar if possible.
# For now, we try accessing without password if configured or rely on .env sourcing.
if [ -f "${SCRIPT_DIR}/.env" ]; then
    source "${SCRIPT_DIR}/.env"
fi

# If password is set, use it.
MYSQL_CMD="mysqldump --all-databases"
if [ -n "$MYSQL_PASSWORD" ]; then
   MYSQL_CMD="mysqldump --all-databases -p$MYSQL_PASSWORD"
fi

if docker exec "$MYSQL_CONTAINER" sh -c "$MYSQL_CMD" > "$BACKUP_DIR/mysql_dump.sql" 2>/dev/null; then
    log_info "MySQL backup successful."
else
    log_warn "MySQL backup failed (is container running?). Proceeding..."
fi

# 3. Backup Vault Data
log_info "Backing up Vault..."
# Vault data is in a volume mapped to local filesystem, or mapped dir.
# infrastructure/docker-compose.yml:
#     volumes:
#       - ./vault/config:/vault/config
#       - ./vault/file:/vault/file
#       - ./vault/logs:/vault/logs
#       - ../ssl/vault:/vault/ssl:ro
# So we can just back up the local directory `infrastructure/vault/file`
# And the keys `infrastructure/vault/keys`

mkdir -p "$BACKUP_DIR/vault"
if [ -d "$VAULT_DATA_DIR" ]; then
    cp -r "$VAULT_DATA_DIR" "$BACKUP_DIR/vault/data"
else
    log_warn "Vault data directory not found at $VAULT_DATA_DIR"
fi

if [ -d "$VAULT_KEYS_DIR" ]; then
    cp -r "$VAULT_KEYS_DIR" "$BACKUP_DIR/vault/keys"
else
    log_error "Vault keys directory not found at $VAULT_KEYS_DIR. Critical!"
fi

# 4. Compress
# 4. Compress & Encrypt
log_info "Compressing and Encrypting backup..."
if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
    log_warn "BACKUP_ENCRYPTION_KEY not set. Creating unencrypted backup (Non-Compliant)."
    tar -czf "${BACKUP_DIR}.tar.gz" -C "$BACKUP_ROOT" "backup_${TIMESTAMP}"
else
    tar -czf - -C "$BACKUP_ROOT" "backup_${TIMESTAMP}" | openssl enc -aes-256-cbc -salt -pbkdf2 -out "${BACKUP_DIR}.tar.gz.enc" -pass pass:"$BACKUP_ENCRYPTION_KEY"
    log_info "Backup encrypted."
fi

rm -rf "$BACKUP_DIR"

if [ -f "${BACKUP_DIR}.tar.gz.enc" ]; then
    log_info "Backup created at ${BACKUP_DIR}.tar.gz.enc"
elif [ -f "${BACKUP_DIR}.tar.gz" ]; then
    log_info "Backup created at ${BACKUP_DIR}.tar.gz"
fi

# 5. Prune old backups (Keep last 7)
log_info "Pruning old backups..."
ls -t "$BACKUP_ROOT"/backup_*.tar.gz | tail -n +8 | xargs -I {} rm -- {} 2>/dev/null || true

log_info "Backup process completed."
