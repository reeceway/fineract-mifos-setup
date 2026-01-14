#!/bin/bash

# =============================================================================
# MIFOS BANK-IN-A-BOX - COMPLETE SHUTDOWN SCRIPT
# =============================================================================

echo "=============================================="
echo "  MIFOS BANK-IN-A-BOX - Stopping All Services"
echo "=============================================="

cd "$(dirname "$0")"

echo "Stopping Infrastructure..."
cd infrastructure && docker-compose down 2>/dev/null; cd ..

echo "Stopping Payment Hub..."
cd payment-hub-ee && docker-compose down 2>/dev/null; cd ..

echo "Stopping Moov..."
cd moov && docker-compose down 2>/dev/null; cd ..

echo "Stopping Marble..."
cd marble && docker-compose down 2>/dev/null; cd ..

echo "Stopping Customer Portal..."
cd customer-portal && docker-compose down 2>/dev/null; cd ..

echo "Stopping Fineract & Mifos..."
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql && docker-compose down 2>/dev/null; cd ../../..

echo ""
echo "=============================================="
echo "  ALL SERVICES STOPPED"
echo "=============================================="