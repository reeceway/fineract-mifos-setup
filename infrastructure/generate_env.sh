#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ADDR="https://127.0.0.1:8200"
VAULT_CONTAINER="mifos-vault"
KEYS_FILE="${SCRIPT_DIR}/vault/keys/init.json"
ENV_FILE="${SCRIPT_DIR}/../.env"

# Logging
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

check_prereqs() {
    for cmd in docker jq; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is required but not installed."
            exit 1
        fi
    done
}

get_secret() {
    local path=$1
    local key=$2
    local secrets_json=$3
    
    val=$(echo "$secrets_json" | jq -r ".data.data.$key")
    if [ "$val" == "null" ] || [ -z "$val" ]; then
        log_error "Failed to extract '$key' from secret '$path'"
        exit 1
    fi
    echo "$val"
}

check_prereqs

if [ ! -f "$KEYS_FILE" ]; then
    log_error "Vault keys file not found at $KEYS_FILE. Please run setup_vault_auto.sh first."
    exit 1
fi

ROOT_TOKEN=$(jq -r .root_token "$KEYS_FILE")
if [ -z "$ROOT_TOKEN" ] || [ "$ROOT_TOKEN" == "null" ]; then
    log_error "Root token not found in keys file."
    exit 1
fi

log_info "Fetching secrets from Vault..."

# Fetch Database Secrets
if ! DB_SECRETS=$(docker exec -e VAULT_TOKEN="$ROOT_TOKEN" -e VAULT_ADDR=$VAULT_ADDR -e VAULT_SKIP_VERIFY=true $VAULT_CONTAINER vault kv get -format=json banking/databases); then
    log_error "Could not fetch banking/databases from Vault. Is Vault unsealed and initialized?"
    exit 1
fi

# Fetch Service Secrets
if ! SVC_SECRETS=$(docker exec -e VAULT_TOKEN="$ROOT_TOKEN" -e VAULT_ADDR=$VAULT_ADDR -e VAULT_SKIP_VERIFY=true $VAULT_CONTAINER vault kv get -format=json banking/services); then
    log_error "Could not fetch banking/services from Vault."
    exit 1
fi

# Extract values
POSTGRES_PASSWORD=$(get_secret "banking/databases" "postgres_password" "$DB_SECRETS")
MYSQL_PASSWORD=$(get_secret "banking/databases" "mysql_password" "$DB_SECRETS")
REDIS_PASSWORD=$(get_secret "banking/databases" "redis_password" "$DB_SECRETS")
ELASTICSEARCH_PASSWORD=$(get_secret "banking/databases" "elasticsearch_password" "$DB_SECRETS")


MINIO_PASSWORD=$(get_secret "banking/services" "minio_password" "$SVC_SECRETS")
KEYCLOAK_PASSWORD=$(get_secret "banking/services" "keycloak_password" "$SVC_SECRETS")
GRAFANA_PASSWORD=$(get_secret "banking/services" "grafana_password" "$SVC_SECRETS")
FINERACT_ADMIN_PASSWORD=$(get_secret "banking/services" "fineract_admin_password" "$SVC_SECRETS")
BACKUP_ENCRYPTION_KEY=$(get_secret "banking/services" "backup_encryption_key" "$SVC_SECRETS")

log_info "Generating .env file..."

cat > "$ENV_FILE" << EOF
# =============================================================================
# MIFOS BANKING STACK - PRODUCTION CREDENTIALS
# =============================================================================
# AUTO-GENERATED FROM VAULT - DO NOT COMMIT TO GIT
# Generated: $(date)
# =============================================================================

# =============================================================================
# CORE FINERACT DATABASE
# =============================================================================
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# =============================================================================
# INFRASTRUCTURE SERVICES
# =============================================================================
# MySQL (Message Gateway, etc.)
MYSQL_PASSWORD=$MYSQL_PASSWORD

# Redis Cache
REDIS_PASSWORD=$REDIS_PASSWORD

# Elasticsearch (Audit Logging)
ELASTICSEARCH_PASSWORD=$ELASTICSEARCH_PASSWORD

# MinIO Document Storage
MINIO_ROOT_USER=minio_admin
MINIO_ROOT_PASSWORD=$MINIO_PASSWORD

# Keycloak Identity Provider
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PASSWORD

# Grafana Monitoring
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASSWORD

# HashiCorp Vault
# Root token is in infrastructure/vault/keys/init.json

# =============================================================================
# FINERACT CREDENTIALS
# =============================================================================
FINERACT_USERNAME=mifos
FINERACT_PASSWORD=$FINERACT_ADMIN_PASSWORD

# =============================================================================
# BACKUP SECURITY
# =============================================================================
BACKUP_ENCRYPTION_KEY=$BACKUP_ENCRYPTION_KEY

EOF

log_info ".env file generated successfully at $ENV_FILE"
