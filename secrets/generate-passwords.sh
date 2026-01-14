#!/bin/bash
# =============================================================================
# MIFOS BANKING STACK - SECURE PASSWORD GENERATOR
# =============================================================================
# Run this script to generate secure passwords for all services
# =============================================================================

set -e

echo "=============================================="
echo "  Generating Secure Passwords"
echo "=============================================="

# Generate secure 32-character passwords
generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
}

# Generate all passwords
POSTGRES_PASSWORD=$(generate_password)
MYSQL_PASSWORD=$(generate_password)
REDIS_PASSWORD=$(generate_password)
ELASTICSEARCH_PASSWORD=$(generate_password)
MINIO_PASSWORD=$(generate_password)
KEYCLOAK_PASSWORD=$(generate_password)
GRAFANA_PASSWORD=$(generate_password)
FINERACT_PASSWORD=$(generate_password)
SESSION_SECRET=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c 64)
VAULT_TOKEN=$(generate_password)
PH_MYSQL_ROOT_PASSWORD=$(generate_password)
PH_MYSQL_PASSWORD=$(generate_password)
PH_ELASTICSEARCH_PASSWORD=$(generate_password)

cat > ../.env << ENVEOF
# =============================================================================
# MIFOS BANKING STACK - PRODUCTION CREDENTIALS
# =============================================================================
# AUTO-GENERATED - DO NOT COMMIT TO GIT
# Generated: $(date)
# =============================================================================

# =============================================================================
# CORE FINERACT DATABASE
# =============================================================================
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# =============================================================================
# INFRASTRUCTURE SERVICES
# =============================================================================
# MySQL (Message Gateway, etc.)
MYSQL_PASSWORD=${MYSQL_PASSWORD}

# Redis Cache
REDIS_PASSWORD=${REDIS_PASSWORD}

# Elasticsearch (Audit Logging)
ELASTICSEARCH_PASSWORD=${ELASTICSEARCH_PASSWORD}

# MinIO Document Storage
MINIO_ROOT_USER=minio_admin
MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}

# Keycloak Identity Provider
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_PASSWORD}

# Grafana Monitoring
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}

# HashiCorp Vault
VAULT_DEV_ROOT_TOKEN_ID=${VAULT_TOKEN}

# =============================================================================
# FINERACT CREDENTIALS
# =============================================================================
FINERACT_USERNAME=mifos
FINERACT_PASSWORD=${FINERACT_PASSWORD}

# =============================================================================
# PAYMENT HUB EE
# =============================================================================
PH_MYSQL_ROOT_PASSWORD=${PH_MYSQL_ROOT_PASSWORD}
PH_MYSQL_PASSWORD=${PH_MYSQL_PASSWORD}
PH_ELASTICSEARCH_PASSWORD=${PH_ELASTICSEARCH_PASSWORD}

# =============================================================================
# MARBLE COMPLIANCE
# =============================================================================
SESSION_SECRET=${SESSION_SECRET}

# =============================================================================
# NOTIFICATION SERVICES (Configure these manually)
# =============================================================================
# Twilio (SMS)
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=

# SMTP (Email)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
ENVEOF

# Create a secure copy for backup
cp ../.env ../.env.backup.$(date +%Y%m%d%H%M%S)

echo ""
echo "=============================================="
echo "  Passwords Generated Successfully"
echo "=============================================="
echo ""
echo "IMPORTANT ACTIONS:"
echo "1. Store these credentials in a secure vault"
echo "2. Ensure .env is in .gitignore"
echo "3. Create encrypted backups"
echo ""
echo "Saved to: .env"
echo "Backup saved to: .env.backup.$(date +%Y%m%d%H%M%S)"
echo ""
echo "=============================================="