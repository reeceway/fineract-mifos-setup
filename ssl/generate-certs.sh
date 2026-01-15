#!/bin/bash
# =============================================================================
# Certificate Generation Script for Banking Infrastructure
# =============================================================================
# Generates CA and service certificates for internal TLS
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_DIR="$SCRIPT_DIR/ca"
VALIDITY_DAYS=365
CA_VALIDITY_DAYS=3650

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Step 1: Generate Certificate Authority (CA)
# =============================================================================
generate_ca() {
    log_info "Generating Certificate Authority..."

    if [ -f "$CA_DIR/ca.key" ]; then
        log_warn "CA already exists, skipping..."
        return
    fi

    mkdir -p "$CA_DIR"

    # Generate CA private key
    openssl genrsa -out "$CA_DIR/ca.key" 4096

    # Generate CA certificate
    openssl req -new -x509 -days $CA_VALIDITY_DAYS -key "$CA_DIR/ca.key" \
        -out "$CA_DIR/ca.crt" \
        -subj "/C=US/ST=State/L=City/O=MifosBank/OU=IT/CN=MifosBank-CA"

    # Set permissions
    chmod 600 "$CA_DIR/ca.key"
    chmod 644 "$CA_DIR/ca.crt"

    log_info "CA generated successfully"
}

# =============================================================================
# Step 2: Generate Service Certificate
# =============================================================================
generate_cert() {
    local SERVICE_NAME=$1
    local COMMON_NAME=$2
    local ALT_NAMES=$3
    local CERT_DIR="$SCRIPT_DIR/$SERVICE_NAME"

    log_info "Generating certificate for $SERVICE_NAME..."

    mkdir -p "$CERT_DIR"

    # Generate private key
    openssl genrsa -out "$CERT_DIR/$SERVICE_NAME.key" 2048

    # Create config with SAN
    cat > "$CERT_DIR/$SERVICE_NAME.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = US
ST = State
L = City
O = MifosBank
OU = IT
CN = $COMMON_NAME

[req_ext]
subjectAltName = @alt_names

[alt_names]
$ALT_NAMES
EOF

    # Generate CSR
    openssl req -new -key "$CERT_DIR/$SERVICE_NAME.key" \
        -out "$CERT_DIR/$SERVICE_NAME.csr" \
        -config "$CERT_DIR/$SERVICE_NAME.cnf"

    # Sign with CA
    openssl x509 -req -in "$CERT_DIR/$SERVICE_NAME.csr" \
        -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
        -CAcreateserial -out "$CERT_DIR/$SERVICE_NAME.crt" \
        -days $VALIDITY_DAYS \
        -extfile "$CERT_DIR/$SERVICE_NAME.cnf" -extensions req_ext

    # Copy CA cert for verification
    cp "$CA_DIR/ca.crt" "$CERT_DIR/ca.crt"

    # Set permissions
    chmod 600 "$CERT_DIR/$SERVICE_NAME.key"
    chmod 644 "$CERT_DIR/$SERVICE_NAME.crt"
    chmod 644 "$CERT_DIR/ca.crt"

    log_info "Certificate for $SERVICE_NAME generated successfully"
}

# =============================================================================
# Step 3: Generate Kafka Keystore/Truststore (Java format)
# =============================================================================
generate_kafka_stores() {
    local CERT_DIR="$SCRIPT_DIR/kafka"
    local STORE_PASSWORD=${KAFKA_SSL_PASSWORD:-"changeit123"}

    log_info "Generating Kafka keystores..."

    # Generate keystore from certificate
    openssl pkcs12 -export \
        -in "$CERT_DIR/kafka.crt" \
        -inkey "$CERT_DIR/kafka.key" \
        -chain -CAfile "$CA_DIR/ca.crt" \
        -name kafka \
        -out "$CERT_DIR/kafka.p12" \
        -password pass:$STORE_PASSWORD

    # Convert to JKS keystore
    keytool -importkeystore \
        -srckeystore "$CERT_DIR/kafka.p12" \
        -srcstoretype PKCS12 \
        -srcstorepass $STORE_PASSWORD \
        -destkeystore "$CERT_DIR/kafka.keystore.jks" \
        -deststoretype JKS \
        -deststorepass $STORE_PASSWORD \
        -noprompt 2>/dev/null || true

    # Create truststore with CA
    keytool -import \
        -file "$CA_DIR/ca.crt" \
        -alias ca \
        -keystore "$CERT_DIR/kafka.truststore.jks" \
        -storepass $STORE_PASSWORD \
        -noprompt 2>/dev/null || true

    # Store password in file for docker-compose
    echo $STORE_PASSWORD > "$CERT_DIR/password"
    chmod 600 "$CERT_DIR/password"

    log_info "Kafka keystores generated successfully"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    log_info "Starting certificate generation..."

    # Generate CA first
    generate_ca

    # Generate service certificates
    generate_cert "kafka" "kafka" "DNS.1 = kafka
DNS.2 = mifos-kafka
DNS.3 = localhost
IP.1 = 127.0.0.1"

    generate_cert "redis" "redis" "DNS.1 = redis
DNS.2 = mifos-redis
DNS.3 = localhost
IP.1 = 127.0.0.1"

    generate_cert "postgres" "postgresql" "DNS.1 = postgresql
DNS.2 = postgres
DNS.3 = mifosx-postgresql-postgresql-1
DNS.4 = keycloak-postgres
DNS.5 = marble-postgres
DNS.6 = localhost
IP.1 = 127.0.0.1"

    generate_cert "mysql" "mysql" "DNS.1 = mysql
DNS.2 = infra-mysql
DNS.3 = ph-mysql
DNS.4 = localhost
IP.1 = 127.0.0.1"

    # Generate Kafka Java keystores (only if keytool available)
    if command -v keytool &> /dev/null; then
        generate_kafka_stores
    else
        log_warn "keytool not found, skipping Kafka keystore generation"
        log_warn "Kafka will use PEM certificates directly"
    fi

    log_info "All certificates generated successfully!"
    log_info ""
    log_info "Certificate locations:"
    log_info "  CA:        $CA_DIR/ca.crt"
    log_info "  Kafka:     $SCRIPT_DIR/kafka/"
    log_info "  Redis:     $SCRIPT_DIR/redis/"
    log_info "  PostgreSQL: $SCRIPT_DIR/postgres/"
    log_info "  MySQL:     $SCRIPT_DIR/mysql/"
}

main "$@"
