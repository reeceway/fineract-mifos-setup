#!/bin/bash
set -e

# Logging
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }

SSL_DIR="ssl/kafka"
PASSWORD="changeit" # Default Java password, or use 'confluent'

if [ -f "$SSL_DIR/kafka.broker.truststore.jks" ] && [ -f "$SSL_DIR/kafka.broker.keystore.jks" ]; then
    log_info "Kafka JKS stores already exist. Skipping generation."
    exit 0
fi

log_info "Generating Kafka JKS stores..."

# 1. Create Truststore (Import CA)
# We use docker to run keytool
docker run --rm -v $(pwd)/ssl:/ssl --entrypoint /bin/sh confluentinc/cp-kafka:7.5.0 -c "
set -e
cd /ssl/kafka

log_info() { echo \"[CONTAINER] \$1\"; }

# Delete existing if any
rm -f kafka.broker.truststore.jks kafka.broker.keystore.jks

# Import CA into Truststore
log_info 'Creating Truststore...'
keytool -noprompt -keystore kafka.broker.truststore.jks \
  -alias CARoot -import -file ca.crt \
  -storepass $PASSWORD -keypass $PASSWORD

# 2. Create Keystore
# Convert PEM to PKCS12 (we do this inside container too for consistency, openssl is likely there)
log_info 'Creating PKCS12...'
openssl pkcs12 -export -in kafka.crt -inkey kafka.key \
  -out kafka.broker.p12 -name kafka \
  -CAfile ca.crt -caname root -passout pass:$PASSWORD

# Import PKCS12 into Keystore
log_info 'Importing into Keystore...'
keytool -importkeystore \
  -deststorepass $PASSWORD -destkeypass $PASSWORD -destkeystore kafka.broker.keystore.jks \
  -srckeystore kafka.broker.p12 -srcstoretype PKCS12 -srcstorepass $PASSWORD \
  -alias kafka

# Clean up p12
rm kafka.broker.p12

# Permissions
chmod 644 kafka.broker.truststore.jks kafka.broker.keystore.jks
"

log_info "Kafka JKS stores generated in $SSL_DIR"
