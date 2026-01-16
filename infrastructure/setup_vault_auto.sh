#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ADDR="https://127.0.0.1:8200"
VAULT_CONTAINER="mifos-vault"
KEYS_DIR="${SCRIPT_DIR}/vault/keys"
INIT_FILE="${KEYS_DIR}/init.json"

# Logging helpers
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Check prerequisites
check_prereqs() {
    for cmd in docker jq openssl; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is required but not installed."
            exit 1
        fi
    done
}

# Run Vault command in container
vault_cmd() {
    # If token argument provided, inject it
    local token_arg=""
    if [ -n "$VAULT_TOKEN" ]; then
        token_arg="-e VAULT_TOKEN=$VAULT_TOKEN"
    fi
    # Use unquoted variable for token_arg to allow it to be empty or contain multiple arguments
    docker exec $token_arg -e VAULT_ADDR=$VAULT_ADDR -e VAULT_SKIP_VERIFY=true $VAULT_CONTAINER vault "$@"
}

wait_for_vault() {
    log_info "Waiting for Vault to be ready..."
    local retries=30
    local count=0
    until vault_cmd status > /dev/null 2>&1 || [ $? -eq 2 ]; do
        sleep 2
        count=$((count + 1))
        if [ $count -ge $retries ]; then
            log_error "Timeout waiting for Vault to start."
            exit 1
        fi
    done
    log_info "Vault is reachable."
}

init_vault() {
    if [ -f "$INIT_FILE" ]; then
        log_info "Init file found at $INIT_FILE. Checking status..."
    fi

    local status_json=$(vault_cmd status -format=json)
    local initialized=$(echo "$status_json" | jq -r .initialized)

    if [ "$initialized" = "false" ]; then
        log_info "Initializing Vault..."
        mkdir -p "$KEYS_DIR"
        local init_output=$(vault_cmd operator init -format=json -key-shares=5 -key-threshold=3)
        echo "$init_output" > "$INIT_FILE"
        chmod 600 "$INIT_FILE"
        log_info "Vault initialized. Keys saved to $INIT_FILE"
    else
        log_info "Vault already initialized."
        if [ ! -f "$INIT_FILE" ]; then
            log_error "Vault is initialized but $INIT_FILE is missing! Cannot unseal or login without keys."
            exit 1
        fi
    fi
}

unseal_vault() {
    if [ ! -f "$INIT_FILE" ]; then
         log_error "Cannot unseal: $INIT_FILE not found."
         exit 1
    fi

    local status_json=$(vault_cmd status -format=json)
    local sealed=$(echo "$status_json" | jq -r .sealed)

    if [ "$sealed" = "true" ]; then
        log_info "Unsealing Vault..."
        local key1=$(jq -r .unseal_keys_b64[0] "$INIT_FILE")
        local key2=$(jq -r .unseal_keys_b64[1] "$INIT_FILE")
        local key3=$(jq -r .unseal_keys_b64[2] "$INIT_FILE")

        vault_cmd operator unseal "$key1" > /dev/null
        vault_cmd operator unseal "$key2" > /dev/null
        vault_cmd operator unseal "$key3" > /dev/null
        log_info "Vault unsealed."
    else
        log_info "Vault is already unsealed."
    fi
}

# We don't login to file anymore, we just set the token variable
set_token() {
     if [ ! -f "$INIT_FILE" ]; then
         log_error "Cannot login: $INIT_FILE not found."
         exit 1
    fi
    ROOT_TOKEN=$(jq -r .root_token "$INIT_FILE")
    export VAULT_TOKEN="$ROOT_TOKEN"
    log_info "Root token loaded."
}

enable_secrets() {
    log_info "Checking secrets engine..."
    if ! vault_cmd secrets list -format=json | jq -e '."banking/"' > /dev/null; then
        log_info "Enabling KV engine at path 'banking'..."
        vault_cmd secrets enable -path=banking kv-v2 || true
    else
        log_info "Secrets engine 'banking' already enabled."
    fi
}

generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
}

store_secrets() {
    log_info "Checking for existing secrets..."
    
    local db_secrets_exist=false
    if vault_cmd kv get banking/databases > /dev/null 2>&1; then
        db_secrets_exist=true
        log_info "Database secrets already exist in Vault. Skipping generation to preserve data integrity."
    fi

    if [ "$db_secrets_exist" = "false" ]; then
        log_info "Generating and storing NEW secrets..."
        
        vault_cmd kv put banking/databases \
          postgres_password="$(generate_password)" \
          mysql_password="$(generate_password)" \
          redis_password="$(generate_password)" \
          elasticsearch_password="$(generate_password)"
          
        vault_cmd kv put banking/services \
          minio_password="$(generate_password)" \
          keycloak_password="$(generate_password)" \
          grafana_password="$(generate_password)" \
          fineract_admin_password="$(generate_password)"
          
        log_info "Secrets generated and stored."
    fi
}

# Main execution
check_prereqs
wait_for_vault
init_vault
unseal_vault
set_token
enable_secrets
store_secrets

log_info "Vault setup completed successfully."
