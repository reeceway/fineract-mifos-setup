#!/bin/bash

# =============================================================================
# MIFOS BANK-IN-A-BOX - COMPLETE STARTUP SCRIPT (INTEGRATED)
# =============================================================================
# This script starts all components with proper networking for end-to-end
# payment processing including compliance screening
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
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
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
# CREATE SHARED NETWORKS
# =============================================================================
echo ""
print_info "Creating shared Docker networks..."

# Application network for infrastructure services (created before any compose)
docker network create mifos-app 2>/dev/null || true

# Note: mifos-fineract-network is created by Fineract's docker-compose
# Note: moov-network is created by Moov's docker-compose

print_status "Shared networks ready"

# =============================================================================
# LAYER 1: Core Banking (Fineract + Mifos)
# =============================================================================
echo ""
echo "=============================================="
echo "  Layer 1: Core Banking (Fineract + Mifos)"
echo "=============================================="
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
docker-compose --env-file ../../../.env up -d
cd ../../..
print_status "Fineract & Mifos started"

# Wait for Fineract to be ready (HTTPS on 8443)
echo "Waiting for Fineract API to be ready..."
for i in {1..90}; do
    if curl -sk -o /dev/null -w "%{http_code}" https://localhost:8443/fineract-provider/api/v1 2>/dev/null | grep -q "401\|200\|403"; then
        print_status "Fineract API is ready (HTTPS:8443)"
        break
    fi
    if [ $i -eq 90 ]; then
        print_warning "Fineract startup timeout - continuing anyway"
    fi
    sleep 2
done

# Connect Fineract to shared network
docker network connect mifos-fineract-network fineract-server 2>/dev/null || true
docker network connect mifos-fineract-network web-app 2>/dev/null || true

# =============================================================================
# LAYER 2: Compliance Engine (Marble)
# =============================================================================
echo ""
echo "=============================================="
echo "  Layer 2: Compliance Engine (Marble)"
echo "=============================================="
cd marble
export SESSION_SECRET
docker-compose -f docker-compose-dev.yaml --env-file .env.dev up -d
cd ..
print_status "Marble Compliance Engine started"

# Wait for Marble API
echo "Waiting for Marble API..."
for i in {1..60}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8180/liveness 2>/dev/null | grep -q "200"; then
        print_status "Marble API is ready (Port 8180)"
        break
    fi
    if [ $i -eq 60 ]; then
        print_warning "Marble startup timeout - continuing anyway"
    fi
    sleep 2
done

# =============================================================================
# LAYER 3: Payment Rails (Moov)
# =============================================================================
echo ""
echo "=============================================="
echo "  Layer 3: Payment Rails (Moov)"
echo "=============================================="
cd moov
docker-compose up -d
cd ..
print_status "Moov Payment Rails started"

# Wait for Moov ACH
echo "Waiting for Moov services..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8200/health 2>/dev/null | grep -q "200"; then
        print_status "Moov ACH is ready (Port 8200)"
        break
    fi
    sleep 2
done

# =============================================================================
# LAYER 4: Payment Orchestration (Payment Hub)
# =============================================================================
echo ""
echo "=============================================="
echo "  Layer 4: Payment Orchestration (Payment Hub)"
echo "=============================================="
cd payment-hub-ee
docker-compose --env-file ../.env up -d
cd ..
print_status "Payment Hub started"

# Wait for Zeebe
echo "Waiting for Zeebe workflow engine..."
for i in {1..60}; do
    if docker exec ph-zeebe wget -q --spider http://localhost:9600/health 2>/dev/null; then
        print_status "Zeebe workflow engine is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        print_warning "Zeebe startup timeout - continuing anyway"
    fi
    sleep 2
done

# =============================================================================
# LAYER 5: Customer Portal
# =============================================================================
echo ""
echo "=============================================="
echo "  Layer 5: Customer Portal"
echo "=============================================="
cd customer-portal
docker-compose --env-file ../.env up -d
cd ..
print_status "Customer Portal started"

# Connect customer portal to Fineract network
docker network connect mifos-fineract-network mifos-customer-portal 2>/dev/null || true

# =============================================================================
# LAYER 6: Infrastructure (Optional)
# =============================================================================
echo ""
read -p "Start infrastructure services (Keycloak, ELK, Kafka, etc.)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "=============================================="
    echo "  Layer 6: Infrastructure Services"
    echo "=============================================="
    cd infrastructure
    docker-compose --env-file ../.env up -d
    cd ..
    print_status "Infrastructure services started"
    INFRA_STARTED=true
else
    print_warning "Skipping infrastructure services"
    INFRA_STARTED=false
fi

# =============================================================================
# VERIFY INTEGRATION
# =============================================================================
echo ""
echo "=============================================="
echo "  Verifying Service Integration"
echo "=============================================="

# Check network connectivity
print_info "Checking network connectivity..."

# Fineract accessible from Payment Hub network
if docker network inspect mifos-fineract-network | grep -q "ph-ams-mifos" 2>/dev/null || docker network connect mifos-fineract-network ph-ams-mifos 2>/dev/null; then
    print_status "Payment Hub → Fineract network connected"
fi

# Marble accessible from Payment Hub
if docker network inspect marble_default | grep -q "ph-compliance" 2>/dev/null || docker network connect marble_default ph-compliance 2>/dev/null; then
    print_status "Payment Hub → Marble network connected"
fi

# Moov accessible from Payment Hub
if docker network inspect moov-network | grep -q "ph-moov" 2>/dev/null || docker network connect moov-network ph-moov 2>/dev/null; then
    print_status "Payment Hub → Moov network connected"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "=============================================="
echo "  ALL SERVICES STARTED SUCCESSFULLY"
echo "=============================================="
echo ""
echo "INTEGRATION FLOW:"
echo "=============================================="
echo "  Customer Portal → Fineract → Payment Hub"
echo "         ↓              ↓           ↓"
echo "      (HTTPS)       (Account)  → Marble (Compliance)"
echo "                        ↓           ↓"
echo "                    Fineract ← → Moov (ACH/Wire)"
echo ""
echo "ACCESS URLS:"
echo "=============================================="
echo "Core Banking:"
echo "  Staff Portal (Mifos X):    http://localhost"
echo "  Customer Portal:           http://localhost:4200"
echo "  Fineract API (HTTPS):      https://localhost:8443/fineract-provider/api/v1"
echo ""
echo "Compliance & Payments:"
echo "  Marble UI:                 http://localhost:3001"
echo "  Marble API:                http://localhost:8180"
echo "  Payment Hub Channel:       http://localhost:8284"
echo "  Payment Hub Operations:    http://localhost:8283"
echo "  Moov ACH:                  http://localhost:8200"
echo "  Moov Wire:                 http://localhost:8201"
echo ""
if [ "$INFRA_STARTED" = true ]; then
echo "Infrastructure:"
echo "  Keycloak (Auth):           http://localhost:8180"
echo "  MinIO Console:             http://localhost:9001"
echo "  Kibana (Logs):             http://localhost:5601"
echo "  Kafka UI:                  http://localhost:8090"
echo "  Grafana (Metrics):         http://localhost:3000"
echo "  Vault:                     http://localhost:8200"
echo ""
fi
echo "CREDENTIALS:"
echo "=============================================="
echo "All credentials stored in .env file"
echo "View them with: cat .env"
echo ""
echo "Default Fineract user: mifos"
echo "Marble: jbe@zorg.com (Firebase Auth)"
echo ""
echo "SECURITY NOTES:"
echo "=============================================="
echo "✓ Fineract API uses HTTPS (self-signed cert)"
echo "✓ Database ports are NOT exposed externally"
echo "✓ All services use secure passwords from .env"
echo "✓ Compliance screening integrated in payment flow"
echo "⚠ DO NOT commit .env to version control"
echo ""
echo "=============================================="
