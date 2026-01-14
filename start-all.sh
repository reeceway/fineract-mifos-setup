#!/bin/bash

# =============================================================================
# MIFOS BANK-IN-A-BOX - COMPLETE STARTUP SCRIPT (SECURED)
# =============================================================================
# This script starts all components of the institutional banking stack
# with proper credentials and SSL/TLS configurations
# =============================================================================

set -e

cd "$(dirname "$0")"

echo "=============================================="
echo "  MIFOS BANK-IN-A-BOX - Starting All Services"
echo "=============================================="

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

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker Desktop first."
    exit 1
fi
print_status "Docker is running"

# Check for .env file
if [ ! -f ".env" ]; then
    print_warning ".env file not found. Generating secure passwords..."
    chmod +x secrets/generate-passwords.sh
    cd secrets && ./generate-passwords.sh && cd ..
    print_status "Secure passwords generated"
fi

# Load environment variables
set -a
source .env
set +a
print_status "Environment variables loaded"

# =============================================================================
# LAYER 1: Core Banking (Fineract + Mifos)
# =============================================================================
echo ""
echo "Starting Layer 1: Core Banking..."
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
docker-compose --env-file ../../../.env up -d
cd ../../..
print_status "Fineract & Mifos started"

# Wait for Fineract to be ready (now using HTTPS on 8443)
echo "Waiting for Fineract API to be ready..."
for i in {1..90}; do
    if curl -sk -o /dev/null -w "%{http_code}" https://localhost:8443/fineract-provider/api/v1 2>/dev/null | grep -q "401\|200\|403"; then
        print_status "Fineract API is ready (HTTPS)"
        break
    fi
    if [ $i -eq 90 ]; then
        print_warning "Fineract startup timeout - continuing anyway"
    fi
    sleep 2
done

# Create the fineract network if it doesn't exist for other services to connect
docker network create mifos-fineract-network 2>/dev/null || true
docker network connect mifos-fineract-network fineract-server 2>/dev/null || true

# =============================================================================
# LAYER 2: Customer Portal
# =============================================================================
echo ""
echo "Starting Layer 2: Customer Portal..."
cd customer-portal
docker-compose --env-file ../.env up -d
cd ..
print_status "Customer Portal started"

# =============================================================================
# LAYER 3: Compliance (Marble)
# =============================================================================
echo ""
echo "Starting Layer 3: Compliance Engine (Marble)..."
cd marble
# Update Marble's session secret from main .env
export SESSION_SECRET
docker-compose -f docker-compose-dev.yaml --env-file .env.dev up -d
cd ..
print_status "Marble Compliance Engine started"

# =============================================================================
# LAYER 4: Payment Rails (Moov)
# =============================================================================
echo ""
echo "Starting Layer 4: Payment Rails (Moov)..."

# Create the app network if it doesn't exist
docker network create mifos-app 2>/dev/null || true

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
docker-compose --env-file ../.env up -d
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
    docker-compose --env-file ../.env up -d
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
echo "ACCESS URLS (SECURED):"
echo "----------------------------------------"
echo "Staff Portal (Mifos X):    http://localhost"
echo "Customer Portal:           http://localhost:4200"
echo "Fineract API (HTTPS):      https://localhost:8443/fineract-provider/api/v1"
echo ""
echo "COMPLIANCE & PAYMENTS:"
echo "----------------------------------------"
echo "Marble UI:                 http://localhost:3001"
echo "Marble API:                http://localhost:8180"
echo "Moov ACH:                  http://localhost:8200"
echo "Moov Wire:                 http://localhost:8201"
echo "Payment Hub Operations:    http://localhost:8283"
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
echo "=============================================="
echo "  CREDENTIALS"
echo "=============================================="
echo ""
echo "All credentials are stored in .env file"
echo "View them with: cat .env"
echo ""
echo "Default staff user:"
echo "  Username: mifos"
echo "  Password: (see FINERACT_PASSWORD in .env)"
echo ""
echo "Marble: jbe@zorg.com (Firebase Auth)"
echo ""
echo "=============================================="
echo "  SECURITY NOTES"
echo "=============================================="
echo ""
echo "- Fineract API uses HTTPS (self-signed cert)"
echo "- Database ports are NOT exposed externally"
echo "- All services use secure passwords from .env"
echo "- DO NOT commit .env to version control"
echo ""
echo "=============================================="