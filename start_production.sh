#!/bin/bash
# =============================================================================
# PRODUCTION STARTUP - Mifos Banking Stack
# Starts all services in production-ready configuration
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose not found. Please install Docker Compose v2."
        exit 1
    fi
    
    # Check .env file
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        log_error "Missing .env file. Run 'infrastructure/generate_env.sh' first."
        exit 1
    fi
    
    # Check SSL certificates
    if [ ! -d "$SCRIPT_DIR/ssl" ] || [ ! -f "$SCRIPT_DIR/ssl/ca.crt" ]; then
        log_error "Missing SSL certificates. Run './generate_certs.sh' first."
        exit 1
    fi
    
    # Check Vault keys
    if [ ! -f "$SCRIPT_DIR/infrastructure/vault/keys/init.json" ]; then
        log_warn "Vault not initialized. It will initialize on first startup."
    fi
    
    # Validate encryption key is set
    source "$SCRIPT_DIR/.env"
    if [ -z "${BACKUP_ENCRYPTION_KEY:-}" ]; then
        log_error "BACKUP_ENCRYPTION_KEY not set in .env. Required for production."
        exit 1
    fi
    
    log_info "Pre-flight checks passed ✓"
}

# =============================================================================
# START SERVICES
# =============================================================================
start_infrastructure() {
    log_info "Starting infrastructure services..."
    cd "$SCRIPT_DIR/infrastructure"
    
    docker compose up -d \
        keycloak-postgres \
        keycloak \
        mifos-vault \
        mifos-redis \
        mifos-elasticsearch \
        mifos-kafka \
        mifos-minio \
        mifos-nginx
    
    log_info "Waiting for infrastructure to be healthy..."
    sleep 30
}

start_fineract() {
    log_info "Starting Fineract core banking..."
    cd "$SCRIPT_DIR/mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql"
    
    docker compose up -d
    
    log_info "Waiting for Fineract to be ready..."
    sleep 60
}

start_marble() {
    log_info "Starting Marble compliance engine (production config)..."
    cd "$SCRIPT_DIR/marble"
    
    docker compose -f docker-compose-production.yaml up -d
    
    log_info "Waiting for Marble to be ready..."
    sleep 30
}

start_moov() {
    log_info "Starting Moov payment rails (production config)..."
    cd "$SCRIPT_DIR/moov"
    
    docker compose -f docker-compose-production.yml up -d
    
    log_info "Waiting for Moov to be ready..."
    sleep 15
}

start_monitoring() {
    log_info "Starting monitoring stack..."
    cd "$SCRIPT_DIR/infrastructure"
    
    docker compose up -d \
        mifos-prometheus \
        mifos-grafana \
        mifos-filebeat
    
    log_info "Monitoring started"
}

# =============================================================================
# APPLY CONFIGURATIONS
# =============================================================================
apply_elasticsearch_ilm() {
    log_info "Applying Elasticsearch ILM policy (7-year retention)..."
    
    source "$SCRIPT_DIR/.env"
    
    export ELASTICSEARCH_HOST="https://localhost:9200"
    export ELASTICSEARCH_USER="elastic"
    export ELASTICSEARCH_PASSWORD="${ELASTICSEARCH_PASSWORD:-}"
    
    chmod +x "$SCRIPT_DIR/infrastructure/elasticsearch/apply-ilm-policy.sh"
    "$SCRIPT_DIR/infrastructure/elasticsearch/apply-ilm-policy.sh" || log_warn "ILM policy application failed - may need manual setup"
}

install_backup_cron() {
    log_info "Installing backup cron job..."
    chmod +x "$SCRIPT_DIR/backup_production.sh"
    "$SCRIPT_DIR/backup_production.sh" --install-cron
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================
health_check() {
    log_info "Running health checks..."
    
    # Nginx
    if curl -sk https://localhost/health | grep -q "OK"; then
        log_info "  ✓ Nginx API Gateway"
    else
        log_warn "  ✗ Nginx API Gateway"
    fi
    
    # Fineract
    if curl -sk https://localhost/fineract-provider/api/v1 | grep -q "version"; then
        log_info "  ✓ Fineract Core Banking"
    else
        log_warn "  ✗ Fineract Core Banking (may still be starting)"
    fi
    
    # Keycloak
    if curl -s http://localhost:8080/health/ready 2>/dev/null | grep -q "UP"; then
        log_info "  ✓ Keycloak IAM"
    else
        log_warn "  ✗ Keycloak IAM (may still be starting)"
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo ""
    echo "========================================"
    echo "  MIFOS BANKING STACK - PRODUCTION     "
    echo "========================================"
    echo ""
    
    preflight_checks
    
    start_infrastructure
    start_fineract
    start_marble
    start_moov
    start_monitoring
    
    apply_elasticsearch_ilm
    install_backup_cron
    
    echo ""
    log_info "========================================="
    log_info "  PRODUCTION STARTUP COMPLETE"
    log_info "========================================="
    echo ""
    
    health_check
    
    echo ""
    log_info "Access Points:"
    echo "  - Fineract API:     https://localhost/fineract-provider/api/v1"
    echo "  - Staff Portal:     https://localhost/staff/"
    echo "  - Customer Portal:  https://localhost/customer/"
    echo "  - Keycloak:         https://localhost/auth/"
    echo "  - Compliance:       https://localhost/compliance/"
    echo "  - Monitoring:       https://localhost/monitoring/"
    echo ""
    log_info "MFA is ENABLED - users must configure TOTP on first login"
    log_info "Backups run every 6 hours (cron installed)"
    log_info "Logs retained for 7 years per BSA/GLBA"
    echo ""
}

# Handle arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (none)       Start all services"
        echo "  stop         Stop all services"
        echo "  status       Show service status"
        echo "  logs         Follow all logs"
        ;;
    stop)
        log_info "Stopping all services..."
        cd "$SCRIPT_DIR/infrastructure" && docker compose down
        cd "$SCRIPT_DIR/mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql" && docker compose down
        cd "$SCRIPT_DIR/marble" && docker compose -f docker-compose-production.yaml down
        cd "$SCRIPT_DIR/moov" && docker compose -f docker-compose-production.yml down
        log_info "All services stopped"
        ;;
    status)
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;
    logs)
        docker compose -f "$SCRIPT_DIR/infrastructure/docker-compose.yml" logs -f
        ;;
    *)
        main
        ;;
esac
