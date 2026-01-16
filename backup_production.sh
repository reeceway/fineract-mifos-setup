#!/bin/bash
# =============================================================================
# Automated Backup Script with Scheduling
# Production-grade backup for banking operations
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${SCRIPT_DIR}/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"
LOG_FILE="${BACKUP_ROOT}/backup.log"

# Load environment variables
if [ -f "${SCRIPT_DIR}/.env" ]; then
    source "${SCRIPT_DIR}/.env"
fi

# Containers
POSTGRES_CONTAINER="mifosx-postgresql-postgresql-1"
MYSQL_CONTAINER="infra-mysql"
VAULT_DATA_DIR="${SCRIPT_DIR}/infrastructure/vault/file"
VAULT_KEYS_DIR="${SCRIPT_DIR}/infrastructure/vault/keys"

# Logging functions
log_info() { echo -e "\033[0;32m[INFO]\033[0m [$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m [$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m [$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Validate encryption key is set
validate_encryption() {
    if [ -z "${BACKUP_ENCRYPTION_KEY:-}" ]; then
        log_error "BACKUP_ENCRYPTION_KEY not set. Aborting - unencrypted backups not allowed in production."
        exit 1
    fi
}

# Create backup directory
init_backup() {
    mkdir -p "$BACKUP_ROOT"
    mkdir -p "$BACKUP_DIR"
    log_info "Starting backup to ${BACKUP_DIR}"
}

# Backup PostgreSQL (Fineract)
backup_postgres() {
    log_info "Backing up PostgreSQL (Fineract)..."
    if docker ps --format '{{.Names}}' | grep -q "$POSTGRES_CONTAINER"; then
        if docker exec "$POSTGRES_CONTAINER" pg_dumpall -c -U postgres > "$BACKUP_DIR/postgres_dump.sql" 2>/dev/null; then
            log_info "PostgreSQL backup successful ($(wc -c < "$BACKUP_DIR/postgres_dump.sql" | xargs) bytes)"
        else
            log_error "PostgreSQL backup failed"
            return 1
        fi
    else
        log_warn "PostgreSQL container not running, skipping"
    fi
}

# Backup MySQL (Message Gateway, etc.)
backup_mysql() {
    log_info "Backing up MySQL..."
    if docker ps --format '{{.Names}}' | grep -q "$MYSQL_CONTAINER"; then
        MYSQL_CMD="mysqldump --all-databases"
        if [ -n "${MYSQL_PASSWORD:-}" ]; then
            MYSQL_CMD="mysqldump --all-databases -p$MYSQL_PASSWORD"
        fi
        if docker exec "$MYSQL_CONTAINER" sh -c "$MYSQL_CMD" > "$BACKUP_DIR/mysql_dump.sql" 2>/dev/null; then
            log_info "MySQL backup successful"
        else
            log_warn "MySQL backup failed (non-critical)"
        fi
    else
        log_warn "MySQL container not running, skipping"
    fi
}

# Backup Vault data and keys (CRITICAL)
backup_vault() {
    log_info "Backing up Vault..."
    mkdir -p "$BACKUP_DIR/vault"
    
    if [ -d "$VAULT_DATA_DIR" ]; then
        cp -r "$VAULT_DATA_DIR" "$BACKUP_DIR/vault/data"
        log_info "Vault data backed up"
    else
        log_warn "Vault data directory not found"
    fi
    
    if [ -d "$VAULT_KEYS_DIR" ]; then
        cp -r "$VAULT_KEYS_DIR" "$BACKUP_DIR/vault/keys"
        log_info "Vault keys backed up (CRITICAL)"
    else
        log_error "Vault keys directory not found - CRITICAL missing backup"
    fi
}

# Backup Keycloak realm config
backup_keycloak() {
    log_info "Backing up Keycloak configuration..."
    mkdir -p "$BACKUP_DIR/keycloak"
    if [ -d "${SCRIPT_DIR}/infrastructure/keycloak" ]; then
        cp -r "${SCRIPT_DIR}/infrastructure/keycloak"/* "$BACKUP_DIR/keycloak/"
        log_info "Keycloak config backed up"
    fi
}

# Compress and encrypt
finalize_backup() {
    log_info "Compressing and encrypting backup..."
    
    tar -czf - -C "$BACKUP_ROOT" "backup_${TIMESTAMP}" | \
        openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -out "${BACKUP_DIR}.tar.gz.enc" \
        -pass pass:"$BACKUP_ENCRYPTION_KEY"
    
    rm -rf "$BACKUP_DIR"
    
    BACKUP_SIZE=$(ls -lh "${BACKUP_DIR}.tar.gz.enc" | awk '{print $5}')
    log_info "Encrypted backup created: ${BACKUP_DIR}.tar.gz.enc ($BACKUP_SIZE)"
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."
    
    if openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
        -in "${BACKUP_DIR}.tar.gz.enc" \
        -pass pass:"$BACKUP_ENCRYPTION_KEY" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
        log_info "Backup verification PASSED"
    else
        log_error "Backup verification FAILED - backup may be corrupted"
        return 1
    fi
}

# Prune old backups (keep last 30 days worth, minimum 7)
prune_old_backups() {
    log_info "Pruning old backups..."
    
    BACKUP_COUNT=$(ls -1 "$BACKUP_ROOT"/backup_*.tar.gz.enc 2>/dev/null | wc -l)
    
    if [ "$BACKUP_COUNT" -gt 30 ]; then
        ls -t "$BACKUP_ROOT"/backup_*.tar.gz.enc | tail -n +31 | xargs -I {} rm -- {} 2>/dev/null || true
        DELETED=$((BACKUP_COUNT - 30))
        log_info "Pruned $DELETED old backups"
    else
        log_info "No backups to prune ($BACKUP_COUNT existing)"
    fi
}

# Send backup status notification (optional)
notify_status() {
    # Placeholder for alerting integration (Slack, PagerDuty, email)
    # Uncomment and configure as needed
    # curl -X POST -H 'Content-type: application/json' \
    #     --data "{\"text\":\"Backup completed: ${BACKUP_DIR}.tar.gz.enc\"}" \
    #     "${SLACK_WEBHOOK_URL}"
    :
}

# Main execution
main() {
    validate_encryption
    init_backup
    
    backup_postgres
    backup_mysql
    backup_vault
    backup_keycloak
    
    finalize_backup
    verify_backup
    prune_old_backups
    notify_status
    
    log_info "Backup process completed successfully"
}

# Run main or show help
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--install-cron]"
        echo ""
        echo "Options:"
        echo "  --install-cron    Install cron job for automated backups"
        echo ""
        echo "Environment variables:"
        echo "  BACKUP_ENCRYPTION_KEY   Required. AES-256 encryption key"
        echo "  MYSQL_PASSWORD          Optional. MySQL root password"
        ;;
    --install-cron)
        CRON_CMD="0 */6 * * * cd ${SCRIPT_DIR} && ./backup_production.sh >> ${BACKUP_ROOT}/cron.log 2>&1"
        (crontab -l 2>/dev/null | grep -v "backup_production.sh"; echo "$CRON_CMD") | crontab -
        echo "Cron job installed for backups every 6 hours"
        echo "View with: crontab -l"
        ;;
    *)
        main
        ;;
esac
