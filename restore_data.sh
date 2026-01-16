#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_FILE=$1
BACKUP_ROOT="${SCRIPT_DIR}/../../backups"
LOG_FILE="${BACKUP_ROOT}/restore.log"

# Services
POSTGRES_CONTAINER="mifosx-postgresql-postgresql-1"
MYSQL_CONTAINER="infra-mysql"
VAULT_CONTAINER="mifos-vault"
VAULT_DATA_DIR="${SCRIPT_DIR}/infrastructure/vault/file"
VAULT_KEYS_DIR="${SCRIPT_DIR}/infrastructure/vault/keys"

# Logging
log_info() { echo -e "\033[0;32m[INFO]\033[0m [$(date)] $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m [$(date)] $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m [$(date)] $1" | tee -a "$LOG_FILE"; }

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <path_to_backup_tar_gz>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

log_info "Starting restore from $BACKUP_FILE..."

# 1. Extract
TEMP_DIR="${BACKUP_ROOT}/restore_temp_$(date +%s)"
mkdir -p "$TEMP_DIR"

if [[ "$BACKUP_FILE" == *.enc ]]; then
    log_info "Detected encrypted backup. Decrypting..."
    if [ -f "${SCRIPT_DIR}/.env" ]; then source "${SCRIPT_DIR}/.env"; fi
    
    if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        log_error "BACKUP_ENCRYPTION_KEY is required to restore encrypted backup."
        exit 1
    fi
    
    openssl enc -d -aes-256-cbc -pbkdf2 -in "$BACKUP_FILE" -pass pass:"$BACKUP_ENCRYPTION_KEY" | tar -xzf - -C "$TEMP_DIR"
else
    tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"
fi

# Find the extracted folder (it will be named backup_YYYYMMDD_HHMMSS)
RESTORE_SOURCE=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "backup_*" | head -n 1)

if [ -z "$RESTORE_SOURCE" ]; then
    log_error "Could not find backup directory inside archive."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 2. Restore PostgreSQL
log_info "Restoring PostgreSQL..."
if [ -f "$RESTORE_SOURCE/postgres_dump.sql" ]; then
    # WARNING: This typically requires dropping existing DBs.
    docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -f - < "$RESTORE_SOURCE/postgres_dump.sql"
    log_info "PostgreSQL restore completed."
else
    log_warn "No PostgreSQL dump found."
fi

# 3. Restore MySQL
log_info "Restoring MySQL..."
if [ -f "$RESTORE_SOURCE/mysql_dump.sql" ]; then
    if [ -f "${SCRIPT_DIR}/.env" ]; then source "${SCRIPT_DIR}/.env"; fi
    MYSQL_CMD="mysql"
    if [ -n "$MYSQL_PASSWORD" ]; then MYSQL_CMD="mysql -p$MYSQL_PASSWORD"; fi
    
    docker exec -i "$MYSQL_CONTAINER" sh -c "$MYSQL_CMD" < "$RESTORE_SOURCE/mysql_dump.sql"
    log_info "MySQL restore completed."
else
    log_warn "No MySQL dump found."
fi

# 4. Restore Vault
log_info "Restoring Vault..."
if [ -d "$RESTORE_SOURCE/vault" ]; then
    log_info "Stopping Vault container..."
    docker stop "$VAULT_CONTAINER"
    
    log_info "Replacing Vault data..."
    rm -rf "$VAULT_DATA_DIR"
    rm -rf "$VAULT_KEYS_DIR"
    
    cp -r "$RESTORE_SOURCE/vault/data" "$VAULT_DATA_DIR"
    cp -r "$RESTORE_SOURCE/vault/keys" "$VAULT_KEYS_DIR"
    
    log_info "Starting Vault container..."
    docker start "$VAULT_CONTAINER"
    
    # Wait for start
    sleep 5
    # Might need unsealing again? Auto-unseal check?
    # Usually restoring data file keeps it sealed, keys are needed to unseal.
    # setup_vault_auto.sh can be run to unseal.
    log_info "Vault restored. You may need to run setup_vault_auto.sh to unseal."
else
    log_warn "No Vault backup found."
fi

# Cleanup
rm -rf "$TEMP_DIR"
log_info "Restore process completed."
