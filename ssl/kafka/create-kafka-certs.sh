#!/bin/bash
# =============================================================================
# Kafka SSL Certificate Generation Script
# =============================================================================
# Following Confluent's official pattern for cp-kafka SSL configuration
# Uses Docker for keytool if Java is not installed locally
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
PASSWORD="${KAFKA_SSL_PASSWORD:-confluent}"
VALIDITY_DAYS=365
CA_VALIDITY_DAYS=3650

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Step 1: Generate CA Certificate (using openssl - no Java needed)
# =============================================================================
generate_ca() {
    log_info "Generating Certificate Authority..."

    # Use existing CA if present in parent ssl/ca directory
    if [ -f "../ca/ca.crt" ] && [ -f "../ca/ca.key" ]; then
        log_info "Using existing CA from ../ca/"
        cp ../ca/ca.crt snakeoil-ca-1.crt
        cp ../ca/ca.key snakeoil-ca-1.key
    else
        # Generate new CA
        openssl req -new -x509 -keyout snakeoil-ca-1.key -out snakeoil-ca-1.crt \
            -days $CA_VALIDITY_DAYS -nodes \
            -subj "/C=US/ST=State/L=City/O=MifosBank/OU=IT/CN=MifosBank-CA"
    fi

    log_info "CA certificate ready"
}

# =============================================================================
# Step 2-5: Generate Keystores using Docker (runs keytool in container)
# =============================================================================
generate_keystores_with_docker() {
    log_info "Generating keystores using Docker (eclipse-temurin:17-jdk)..."

    # Create a temporary script to run inside Docker
    cat > /tmp/generate-keystores.sh << 'SCRIPT'
#!/bin/bash
set -e
cd /certs
PASSWORD="$1"
VALIDITY_DAYS="$2"

echo "==> Generating broker keystore..."
rm -f kafka.broker.keystore.jks
keytool -genkey -noprompt \
    -alias broker \
    -dname "CN=kafka,OU=IT,O=MifosBank,L=City,ST=State,C=US" \
    -ext "SAN=DNS:kafka,DNS:mifos-kafka,DNS:localhost,IP:127.0.0.1" \
    -keystore kafka.broker.keystore.jks \
    -keyalg RSA \
    -keysize 2048 \
    -validity $VALIDITY_DAYS \
    -storepass "$PASSWORD" \
    -keypass "$PASSWORD" \
    -storetype JKS

echo "==> Exporting CSR..."
keytool -certreq -noprompt \
    -alias broker \
    -keystore kafka.broker.keystore.jks \
    -file broker.csr \
    -storepass "$PASSWORD" \
    -keypass "$PASSWORD"

echo "==> Signing with CA..."
openssl x509 -req -CA snakeoil-ca-1.crt -CAkey snakeoil-ca-1.key \
    -in broker.csr -out broker-ca1-signed.crt \
    -days $VALIDITY_DAYS -CAcreateserial \
    -extfile <(printf "subjectAltName=DNS:kafka,DNS:mifos-kafka,DNS:localhost,IP:127.0.0.1")

echo "==> Importing CA into keystore..."
keytool -import -noprompt \
    -alias CARoot \
    -file snakeoil-ca-1.crt \
    -keystore kafka.broker.keystore.jks \
    -storepass "$PASSWORD"

echo "==> Importing signed cert into keystore..."
keytool -import -noprompt \
    -alias broker \
    -file broker-ca1-signed.crt \
    -keystore kafka.broker.keystore.jks \
    -storepass "$PASSWORD"

echo "==> Generating truststore..."
rm -f kafka.broker.truststore.jks
keytool -import -noprompt \
    -alias CARoot \
    -file snakeoil-ca-1.crt \
    -keystore kafka.broker.truststore.jks \
    -storepass "$PASSWORD" \
    -storetype JKS

echo "==> Listing keystore..."
keytool -list -keystore kafka.broker.keystore.jks -storepass "$PASSWORD" | head -10

echo "==> Listing truststore..."
keytool -list -keystore kafka.broker.truststore.jks -storepass "$PASSWORD" | head -10

echo "==> Cleanup..."
rm -f broker.csr broker-ca1-signed.crt snakeoil-ca-1.srl

echo "==> Done!"
SCRIPT

    chmod +x /tmp/generate-keystores.sh

    # Run in Docker
    docker run --rm \
        -v "$SCRIPT_DIR:/certs" \
        -v "/tmp/generate-keystores.sh:/generate-keystores.sh:ro" \
        eclipse-temurin:17-jdk \
        /bin/bash /generate-keystores.sh "$PASSWORD" "$VALIDITY_DAYS"

    log_info "Keystores generated"
}

# =============================================================================
# Step 6: Create Credential Files
# =============================================================================
create_credential_files() {
    log_info "Creating credential files..."

    # Credential files for Confluent Kafka (plain text password)
    echo "$PASSWORD" > broker_sslkey_creds
    echo "$PASSWORD" > broker_keystore_creds
    echo "$PASSWORD" > broker_truststore_creds

    # Set permissions
    chmod 600 broker_sslkey_creds broker_keystore_creds broker_truststore_creds

    log_info "Credential files created"
}

# =============================================================================
# Main
# =============================================================================
main() {
    log_info "Starting Kafka SSL certificate generation..."
    log_info "Password: $PASSWORD"

    generate_ca
    generate_keystores_with_docker
    create_credential_files

    log_info ""
    log_info "=== Certificate Generation Complete ==="
    log_info "Files created:"
    ls -la *.jks *_creds 2>/dev/null || true
    log_info ""
    log_info "Mount these files to /etc/kafka/secrets in the Kafka container"
}

main "$@"
