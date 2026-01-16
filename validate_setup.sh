#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/validation.log"

# Services
SERVICES=("mifos-vault" "mifos-nginx" "mifosx-postgresql-postgresql-1" "infra-mysql" "mifos-kafka" "mifos-redis" "mifosx-postgresql-fineract-server-1")

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1" | tee -a "$LOG_FILE"; }
log_fail() { echo -e "\033[0;31m[FAIL]\033[0m $1" | tee -a "$LOG_FILE"; }
log_pass() { echo -e "\033[0;32m[PASS]\033[0m $1" | tee -a "$LOG_FILE"; }

log_info "Starting System Validation..."

# 1. Check Containers
log_info "[1/4] Checking Service Health..."
ALL_RUNNING=true
for svc in "${SERVICES[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
        log_pass "Service $svc is running."
    else
        log_fail "Service $svc is NOT running."
        ALL_RUNNING=false
    fi
done

# 2. Check Vault Status
log_info "[2/4] Checking Vault Status..."
VAULT_ENV="-e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_SKIP_VERIFY=true"
if docker exec $VAULT_ENV mifos-vault vault status > /dev/null 2>&1; then
    SEALED=$(docker exec $VAULT_ENV mifos-vault vault status -format=json | jq -r .sealed)
    if [ "$SEALED" = "false" ]; then
        log_pass "Vault is unsealed and operational."
    else
        log_fail "Vault is SEALED."
    fi
else
    log_fail "Vault is not responding."
fi

# 3. Check TLS Certificates
log_info "[3/4] Checking TLS Certificates..."
CERTS=("postgres" "mysql" "redis" "kafka" "fineract" "vault" "nginx")
MISSING_CERTS=false
for cert in "${CERTS[@]}"; do
    if [ -f "ssl/$cert/$cert.crt" ] && [ -f "ssl/$cert/$cert.key" ]; then
        log_pass "Certificate for $cert exists."
    else
        log_fail "Certificate for $cert is MISSING."
        MISSING_CERTS=true
    fi
done

# 4. Check Fineract API Reachability
log_info "[4/4] Checking Fineract API Reachability..."
# Wait a bit just in case
# Using -k (insecure) because of self-signed certs
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/fineract-provider/actuator/health || echo "000")

if [[ "$HTTP_CODE" =~ 200 ]]; then
    log_pass "Fineract API is reachable (HTTP 200)."
elif [[ "$HTTP_CODE" == "000" ]]; then
    log_fail "Fineract API is unreachable (Connection failed)."
else
     log_fail "Fineract API returned HTTP $HTTP_CODE (Expected 200)."
fi

echo "---------------------------------------------------"
if [ "$ALL_RUNNING" = "true" ] && [ "$SEALED" = "false" ] && [ "$MISSING_CERTS" = "false" ] && [[ "$HTTP_CODE" =~ 200 ]]; then
    log_info "SYSTEM VALIDATION SUCCESSFUL: All checks passed."
    exit 0
else
    log_fail "SYSTEM VALIDATION FAILED: See logs above."
    exit 1
fi
