#!/bin/bash
set -e

# Logging
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }

# Create directories
mkdir -p ssl/{postgres,mysql,redis,kafka,fineract,vault,nginx}

# 1. Generate Root CA
if [ -f "ssl/ca.key" ] && [ -f "ssl/ca.crt" ]; then
    log_info "Root CA already exists. Skipping generation."
else
    log_info "Generating Root CA..."
    openssl genrsa -out ssl/ca.key 4096
    openssl req -x509 -new -nodes -key ssl/ca.key -sha256 -days 3650 -out ssl/ca.crt -subj "/CN=Mifos-Banking-Root-CA/O=MifosBank/C=US"
fi

# Function to generate certs
generate_cert() {
    SERVICE=$1
    CN=$2
    DIR="ssl/$SERVICE"
    
    if [ -f "$DIR/$SERVICE.crt" ] && [ -f "$DIR/$SERVICE.key" ]; then
        log_info "Certificate for $SERVICE already exists. Skipping."
        return
    fi
    
    log_info "Generating certificate for $SERVICE ($CN)..."
    openssl genrsa -out $DIR/$SERVICE.key 2048
    openssl req -new -key $DIR/$SERVICE.key -out $DIR/$SERVICE.csr -subj "/CN=$CN/O=MifosBank/C=US"
    
    # Create config for SANs
    cat > $DIR/$SERVICE.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN
DNS.2 = localhost
DNS.3 = host.docker.internal
DNS.4 = $SERVICE
IP.1 = 127.0.0.1
EOF

    openssl x509 -req -in $DIR/$SERVICE.csr -CA ssl/ca.crt -CAkey ssl/ca.key -CAcreateserial \
    -out $DIR/$SERVICE.crt -days 365 -sha256 -extfile $DIR/$SERVICE.ext
    
    # Copy CA to service dir
    cp ssl/ca.crt $DIR/ca.crt
    
    # Set permissions
    chmod 644 $DIR/$SERVICE.crt $DIR/ca.crt
    chmod 600 $DIR/$SERVICE.key
}

# 2. Generate Service Certificates
generate_cert "postgres" "postgresql"
generate_cert "mysql" "mysql"
generate_cert "redis" "redis"
generate_cert "kafka" "kafka"
generate_cert "fineract" "fineract-server"
generate_cert "vault" "vault"
generate_cert "nginx" "nginx"

# Special handling for Postgres (key permission)
chmod 600 ssl/postgres/postgres.key 2>/dev/null || true

log_info "All certificates are up to date."
