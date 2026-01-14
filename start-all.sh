#!/bin/bash

# =============================================================================
# MIFOS BANK-IN-A-BOX - COMPLETE STARTUP SCRIPT
# =============================================================================
# This script starts all components of the institutional banking stack
# =============================================================================

set -e

echo "=============================================="
echo "  MIFOS BANK-IN-A-BOX - Starting All Services"
echo "=============================================="

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker Desktop first."
    exit 1
fi

print_status "Docker is running"

# =============================================================================
# LAYER 1: Core Banking (Fineract + Mifos)
# =============================================================================
echo ""
echo "Starting Layer 1: Core Banking..."
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
docker-compose up -d
cd ../../..
print_status "Fineract & Mifos started"

# Wait for Fineract to be ready
echo "Waiting for Fineract API to be ready..."
for i in {1..60}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/fineract-provider/api/v1 2>/dev/null | grep -q "401\|200\|403"; then
        print_status "Fineract API is ready"
        break
    fi
    sleep 3
done

# =============================================================================
# LAYER 2: Customer Portal
# =============================================================================
echo ""
echo "Starting Layer 2: Customer Portal..."
cd customer-portal
docker-compose up -d
cd ..
print_status "Customer Portal started"

# =============================================================================
# LAYER 3: Compliance (Marble)
# =============================================================================
echo ""
echo "Starting Layer 3: Compliance Engine (Marble)..."
cd marble
docker-compose -f docker-compose-dev.yaml --env-file .env.dev up -d
cd ..
print_status "Marble Compliance Engine started"

# =============================================================================
# LAYER 4: Payment Rails (Moov)
# =============================================================================
echo ""
echo "Starting Layer 4: Payment Rails (Moov)..."
cd moov
docker-compose up -d
cd ..
print_status "Moov Payment Rails started"

# =============================================================================
# LAYER 5: Payment Orchestration (Payment Hub)
# =============================================================================
echo ""
echo "Starting Layer 5: Payment Orchestration..."
cd payment-hub-ee
docker-compose up -d
cd ..
print_status "Payment Hub started"

# =============================================================================
# LAYER 6: Infrastructure (Optional - requires more resources)
# =============================================================================
echo ""
read -p "Start infrastructure services (Keycloak, ELK, Kafka, etc.)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting Layer 6: Infrastructure..."
    cd infrastructure
    docker-compose up -d
    cd ..
    print_status "Infrastructure services started"
else
    print_warning "Skipping infrastructure services"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "=============================================="
echo "  ALL SERVICES STARTED SUCCESSFULLY"
echo "=============================================="
echo ""
echo "ACCESS URLS:"
echo "----------------------------------------"
echo "Staff Portal (Mifos X):    http://localhost"
echo "Customer Portal:           http://localhost:4200"
echo "Fineract API:              http://localhost:8080/fineract-provider/api/v1"
echo ""
echo "COMPLIANCE & PAYMENTS:"
echo "----------------------------------------"
echo "Marble UI:                 http://localhost:3001"
echo "Marble API:                http://localhost:8180"
echo "Moov ACH:                  http://localhost:8200"
echo "Moov Wire:                 http://localhost:8201"
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
echo "INFRASTRUCTURE:"
echo "----------------------------------------"
echo "Keycloak (Auth):           http://localhost:8180"
echo "MinIO Console:             http://localhost:9001"
echo "Kibana (Logs):             http://localhost:5601"
echo "Kafka UI:                  http://localhost:8090"
echo "Grafana (Metrics):         http://localhost:3000"
echo "Vault:                     http://localhost:8200"
echo ""
fi
echo "DEFAULT CREDENTIALS:"
echo "----------------------------------------"
echo "Mifos:     mifos / password"
echo "Marble:    jbe@zorg.com (Firebase Auth)"
echo "Keycloak:  admin / admin"
echo "MinIO:     minio_admin / minio_password"
echo "Grafana:   admin / admin"
echo ""
echo "=============================================="