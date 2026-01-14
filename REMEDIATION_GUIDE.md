# Step-by-Step Remediation Guide

## How to Use This Guide

Each step follows this pattern:
1. **Understand** - What's the problem and why it matters
2. **Fix** - Exact commands and changes to make
3. **Verify** - How to confirm the fix works
4. **Integration Check** - Ensure everything still works together
5. **Move On** - Only proceed when verification passes

**Rule: Never move to the next step until the current step's verification passes.**

---

## Phase 1: Secrets Management

### Step 1.1: Set Up HashiCorp Vault for Production

#### Understand
Currently, all passwords are hardcoded in docker-compose files and committed to git. Anyone with repo access has database credentials. This violates PCI-DSS and is the #1 security risk.

#### Fix

```bash
# 1. Create production Vault configuration
mkdir -p /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure/vault/config

cat > /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure/vault/config/vault.hcl << 'EOF'
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 0
  tls_cert_file = "/vault/ssl/vault.crt"
  tls_key_file  = "/vault/ssl/vault.key"
}

api_addr = "https://vault:8200"
cluster_addr = "https://vault:8201"
ui = true
EOF

# 2. Generate Vault SSL certificate
mkdir -p /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure/vault/ssl
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure/vault/ssl

openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout vault.key -out vault.crt \
  -subj "/CN=vault/O=MifosBank/C=US"

# 3. Update Vault in docker-compose to use production mode
```

Edit `infrastructure/docker-compose.yml`, replace the Vault service:

```yaml
vault:
  image: hashicorp/vault:1.15
  container_name: mifos-vault
  restart: always
  ports:
    - "8200:8200"
  environment:
    - VAULT_ADDR=https://127.0.0.1:8200
    - VAULT_SKIP_VERIFY=true  # Remove in production with real certs
  cap_add:
    - IPC_LOCK
  volumes:
    - vault-data:/vault/data
    - ./vault/config:/vault/config:ro
    - ./vault/ssl:/vault/ssl:ro
  command: server -config=/vault/config/vault.hcl
  networks:
    - banking-network
```

```bash
# 4. Start Vault
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure
docker-compose up -d vault

# 5. Initialize Vault (do this ONCE, save the keys securely!)
docker exec -it mifos-vault vault operator init

# SAVE THE UNSEAL KEYS AND ROOT TOKEN SECURELY
# You need 3 of 5 keys to unseal

# 6. Unseal Vault (need 3 keys)
docker exec -it mifos-vault vault operator unseal <key1>
docker exec -it mifos-vault vault operator unseal <key2>
docker exec -it mifos-vault vault operator unseal <key3>

# 7. Login with root token
docker exec -it mifos-vault vault login <root_token>

# 8. Enable KV secrets engine
docker exec -it mifos-vault vault secrets enable -path=banking kv-v2
```

#### Verify

```bash
# Check Vault is running and unsealed
docker exec -it mifos-vault vault status

# Expected output should show:
# Sealed: false
# Initialized: true
```

#### Integration Check

```bash
# Vault should be accessible
curl -k https://localhost:8200/v1/sys/health

# Expected: {"initialized":true,"sealed":false,...}
```

**CHECKPOINT: Vault is running, unsealed, and accessible. Do not proceed until this works.**

---

### Step 1.2: Generate New Secure Passwords

#### Understand
We need to generate new strong passwords for all services and store them in Vault. The old hardcoded passwords must never be used again.

#### Fix

```bash
# 1. Generate secure passwords (32 characters each)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
MYSQL_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
MINIO_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
KEYCLOAK_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
FINERACT_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
ELASTICSEARCH_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)

# 2. Store in Vault
docker exec -it mifos-vault vault kv put banking/databases \
  postgres_password="$POSTGRES_PASSWORD" \
  mysql_password="$MYSQL_PASSWORD" \
  redis_password="$REDIS_PASSWORD" \
  elasticsearch_password="$ELASTICSEARCH_PASSWORD"

docker exec -it mifos-vault vault kv put banking/services \
  minio_password="$MINIO_PASSWORD" \
  keycloak_password="$KEYCLOAK_PASSWORD" \
  grafana_password="$GRAFANA_PASSWORD" \
  fineract_admin_password="$FINERACT_ADMIN_PASSWORD"

# 3. Save passwords locally for initial setup (DELETE AFTER USE)
cat > /tmp/passwords.txt << EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
MINIO_PASSWORD=$MINIO_PASSWORD
KEYCLOAK_PASSWORD=$KEYCLOAK_PASSWORD
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
FINERACT_ADMIN_PASSWORD=$FINERACT_ADMIN_PASSWORD
ELASTICSEARCH_PASSWORD=$ELASTICSEARCH_PASSWORD
EOF

echo "Passwords saved to /tmp/passwords.txt - DELETE AFTER SETUP"
```

#### Verify

```bash
# Retrieve passwords from Vault to confirm they're stored
docker exec -it mifos-vault vault kv get banking/databases
docker exec -it mifos-vault vault kv get banking/services

# Should show all stored secrets
```

#### Integration Check

```bash
# Vault should respond with secrets
docker exec -it mifos-vault vault kv get -format=json banking/databases | jq '.data.data'
```

**CHECKPOINT: All new passwords are generated and stored in Vault. Do not proceed until verified.**

---

### Step 1.3: Create Environment File (Not Committed to Git)

#### Understand
We need a `.env` file that docker-compose will use to inject secrets. This file must NEVER be committed to git.

#### Fix

```bash
# 1. Create .env file from passwords
cd /Users/reeceway/Desktop/fineract-mifos-setup

cat > .env << EOF
# AUTO-GENERATED - DO NOT COMMIT TO GIT
# Retrieve from Vault if lost

# Database Passwords
POSTGRES_PASSWORD=$(grep POSTGRES_PASSWORD /tmp/passwords.txt | cut -d= -f2)
MYSQL_PASSWORD=$(grep MYSQL_PASSWORD /tmp/passwords.txt | cut -d= -f2)
REDIS_PASSWORD=$(grep REDIS_PASSWORD /tmp/passwords.txt | cut -d= -f2)
ELASTICSEARCH_PASSWORD=$(grep ELASTICSEARCH_PASSWORD /tmp/passwords.txt | cut -d= -f2)

# Service Passwords
MINIO_ROOT_PASSWORD=$(grep MINIO_PASSWORD /tmp/passwords.txt | cut -d= -f2)
KEYCLOAK_ADMIN_PASSWORD=$(grep KEYCLOAK_PASSWORD /tmp/passwords.txt | cut -d= -f2)
GRAFANA_ADMIN_PASSWORD=$(grep GRAFANA_PASSWORD /tmp/passwords.txt | cut -d= -f2)
FINERACT_ADMIN_PASSWORD=$(grep FINERACT_ADMIN_PASSWORD /tmp/passwords.txt | cut -d= -f2)

# Keep these defaults for now, change in production
MINIO_ROOT_USER=minio_admin
KEYCLOAK_ADMIN=admin
EOF

# 2. Add .env to .gitignore (should already be there, but make sure)
echo ".env" >> .gitignore
echo ".env.local" >> .gitignore
echo ".env.production" >> .gitignore

# 3. Remove the temporary password file
rm /tmp/passwords.txt
```

#### Verify

```bash
# Check .env exists and has values
cat .env | head -5

# Check .gitignore includes .env
grep "^.env$" .gitignore
```

#### Integration Check

```bash
# Ensure .env won't be committed
git status | grep ".env"
# Should show nothing (file is ignored)
```

**CHECKPOINT: .env file created and git-ignored. Do not proceed until verified.**

---

### Step 1.4: Update Fineract Docker Compose to Use Environment Variables

#### Understand
The Fineract docker-compose has hardcoded passwords. We need to replace them with environment variable references.

#### Fix

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup/mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
```

Edit `docker-compose.yml` and replace ALL hardcoded passwords:

**Find and Replace:**

| Find | Replace With |
|------|-------------|
| `POSTGRES_PASSWORD=skdcnwauicn2ucnaecasdsajdnizucawencascdca` | `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}` |
| `FINERACT_HIKARI_PASSWORD=skdcnwauicn2ucnaecasdsajdnizucawencascdca` | `FINERACT_HIKARI_PASSWORD=${POSTGRES_PASSWORD}` |
| `FINERACT_DEFAULT_TENANTDB_PWD=skdcnwauicn2ucnaecasdsajdnizucawencascdca` | `FINERACT_DEFAULT_TENANTDB_PWD=${POSTGRES_PASSWORD}` |

Also edit `fineract-db/docker/postgresql.env`:

```bash
cat > fineract-db/docker/postgresql.env << 'EOF'
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
FINERACT_DB_USER=postgres
FINERACT_DB_PASS=${POSTGRES_PASSWORD}
FINERACT_TENANTS_DB_NAME=fineract_tenants
FINERACT_TENANT_DEFAULT_DB_NAME=fineract_default
EOF
```

Create a symlink to the main .env file:

```bash
ln -sf ../../../.env .env
```

#### Verify

```bash
# Check no hardcoded passwords remain
grep -r "skdcnwauicn2ucnaecasdsajdnizucawencascdca" .
# Should return nothing

# Check environment variables are used
grep "POSTGRES_PASSWORD" docker-compose.yml
# Should show ${POSTGRES_PASSWORD}
```

#### Integration Check

```bash
# Stop existing containers
docker-compose down

# Start with new configuration
docker-compose up -d

# Wait for startup
sleep 30

# Check Fineract is running
curl -s http://localhost:8080/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password | head -1

# Should return office data (we'll change the API password later)
```

**CHECKPOINT: Fineract starts with environment variable passwords. Do not proceed until verified.**

---

### Step 1.5: Update All Other Services to Use Environment Variables

#### Understand
We need to update every docker-compose file to use environment variables instead of hardcoded passwords.

#### Fix

**1. Update infrastructure/docker-compose.yml:**

Replace ALL hardcoded passwords with environment variables:

```yaml
# Keycloak
environment:
  - KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
  - KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}

# Keycloak Postgres
environment:
  - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# MinIO
environment:
  - MINIO_ROOT_USER=${MINIO_ROOT_USER:-minio_admin}
  - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Redis
command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}

# Grafana
environment:
  - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# Elasticsearch (when security enabled)
environment:
  - ELASTIC_PASSWORD=${ELASTICSEARCH_PASSWORD}

# MySQL
environment:
  - MYSQL_ROOT_PASSWORD=${MYSQL_PASSWORD}
```

**2. Update payment-hub-ee/docker-compose.yml:**

```yaml
# MySQL
environment:
  - MYSQL_ROOT_PASSWORD=${MYSQL_PASSWORD}
  - MYSQL_PASSWORD=${MYSQL_PASSWORD}

# AMS-Mifos connector
environment:
  - FINERACT_PASSWORD=${FINERACT_ADMIN_PASSWORD}
```

**3. Update marble/.env.dev:**

```bash
# Generate a real session secret
SESSION_SECRET=$(openssl rand -base64 32)
echo "SESSION_SECRET=$SESSION_SECRET" >> /Users/reeceway/Desktop/fineract-mifos-setup/.env
```

**4. Create symlinks to .env in each directory:**

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup
ln -sf ../.env infrastructure/.env
ln -sf ../.env payment-hub-ee/.env
ln -sf ../.env moov/.env
ln -sf ../.env customer-portal/.env
```

#### Verify

```bash
# Search entire project for hardcoded passwords
cd /Users/reeceway/Desktop/fineract-mifos-setup
grep -r "skdcnwauicn2ucnaecasdsajdnizucawencascdca" --include="*.yml" --include="*.yaml" .
grep -r "mysql_password" --include="*.yml" --include="*.yaml" . | grep -v "\${"
grep -r "admin.*admin" --include="*.yml" --include="*.yaml" . | grep -v "\${" | grep -v "#"

# All should return nothing
```

#### Integration Check

```bash
# Stop all services
./stop-all.sh

# Start all services
./start-all.sh

# Wait for startup
sleep 60

# Check each service is running
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(Up|Restarting)"

# All should show "Up"
```

**CHECKPOINT: All services use environment variables. No hardcoded passwords remain. Do not proceed until verified.**

---

## Phase 2: SSL/TLS Encryption

### Step 2.1: Enable SSL on Fineract

#### Understand
Fineract API currently runs on HTTP (unencrypted). All banking data is transmitted in plaintext. This violates PCI-DSS Requirement 4.

#### Fix

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup/mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
```

Edit `docker-compose.yml`, change the Fineract environment:

```yaml
fineract-server:
  environment:
    # Change this line
    - FINERACT_SERVER_SSL_ENABLED=true
    - FINERACT_SERVER_PORT=8443
  ports:
    # Change port mapping
    - "8443:8443"
```

#### Verify

```bash
# Restart Fineract
docker-compose down
docker-compose up -d

# Wait for startup
sleep 60

# Test HTTPS connection (will have cert warning since self-signed)
curl -k https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password

# Should return office data
```

#### Integration Check

```bash
# Verify HTTP no longer works
curl http://localhost:8080/fineract-provider/api/v1/offices 2>&1 | grep -i "refused\|error"
# Should show connection refused

# Verify HTTPS works
curl -k https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password | jq '.[0].name'
# Should show "Head Office"
```

**CHECKPOINT: Fineract runs on HTTPS. HTTP is disabled. Do not proceed until verified.**

---

### Step 2.2: Update All Services to Connect via HTTPS

#### Understand
Now that Fineract uses HTTPS, all services that connect to it must be updated.

#### Fix

**1. Update customer-portal/docker-compose.yml:**

```yaml
environment:
  - FINERACT_API_URL=https://host.docker.internal:8443
```

**2. Update payment-hub-ee/docker-compose.yml (ams-mifos connector):**

```yaml
ams-mifos:
  environment:
    - FINERACT_BASE_URL=https://host.docker.internal:8443
```

**3. Update Mifos web-app (in mifosplatform docker-compose):**

```yaml
web-app:
  environment:
    - FINERACT_API_URLS=https://localhost:8443
    - FINERACT_API_URL=https://localhost:8443
```

#### Verify

```bash
# Restart affected services
cd /Users/reeceway/Desktop/fineract-mifos-setup/customer-portal
docker-compose down && docker-compose up -d

cd /Users/reeceway/Desktop/fineract-mifos-setup/payment-hub-ee
docker-compose down && docker-compose up -d
```

#### Integration Check

```bash
# Test customer portal can reach Fineract
curl http://localhost:4200 | grep -i "mifos\|fineract"

# Test staff portal can reach Fineract
curl http://localhost | grep -i "mifos\|fineract"

# Both should load without errors
```

**CHECKPOINT: All services connect to Fineract via HTTPS. Do not proceed until verified.**

---

### Step 2.3: Enable SSL on PostgreSQL

#### Understand
Database connections are unencrypted. An attacker on the network can see all SQL queries and data.

#### Fix

```bash
# 1. Generate PostgreSQL SSL certificates
cd /Users/reeceway/Desktop/fineract-mifos-setup/mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql

mkdir -p ssl
cd ssl

# Generate CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt -subj "/CN=PostgreSQL-CA"

# Generate server cert
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr -subj "/CN=postgresql"
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt

# Set permissions
chmod 600 server.key
chmod 644 server.crt ca.crt
```

**2. Create PostgreSQL SSL configuration:**

```bash
cat > postgresql-ssl.conf << 'EOF'
ssl = on
ssl_cert_file = '/var/lib/postgresql/ssl/server.crt'
ssl_key_file = '/var/lib/postgresql/ssl/server.key'
ssl_ca_file = '/var/lib/postgresql/ssl/ca.crt'
EOF
```

**3. Update docker-compose.yml to mount SSL certs:**

```yaml
postgresql:
  volumes:
    - ./ssl:/var/lib/postgresql/ssl:ro
    - ./postgresql-ssl.conf:/etc/postgresql/conf.d/ssl.conf:ro
  command: >
    postgres
    -c ssl=on
    -c ssl_cert_file=/var/lib/postgresql/ssl/server.crt
    -c ssl_key_file=/var/lib/postgresql/ssl/server.key
```

**4. Update Fineract to require SSL:**

```yaml
fineract-server:
  environment:
    - FINERACT_HIKARI_JDBC_URL=jdbc:postgresql://postgresql:5432/fineract_tenants?sslmode=require
```

#### Verify

```bash
# Restart PostgreSQL and Fineract
docker-compose down
docker-compose up -d

# Wait for startup
sleep 30

# Check PostgreSQL SSL is enabled
docker exec -it mifosx-postgresql-postgresql-1 psql -U postgres -c "SHOW ssl;"
# Should show: on

# Check Fineract can still connect
curl -k https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password
```

#### Integration Check

```bash
# Verify Fineract API still works
curl -k https://localhost:8443/fineract-provider/api/v1/clients \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password | head -1

# Verify database queries work (create a test client)
curl -k -X POST https://localhost:8443/fineract-provider/api/v1/clients \
  -H "Fineract-Platform-TenantId: default" \
  -H "Content-Type: application/json" \
  -u mifos:password \
  -d '{"officeId":1,"firstname":"Test","lastname":"User","active":true,"activationDate":"01 January 2024","dateFormat":"dd MMMM yyyy","locale":"en"}'
```

**CHECKPOINT: PostgreSQL uses SSL. Fineract connects via SSL. Do not proceed until verified.**

---

### Step 2.4: Enable Elasticsearch Security

#### Understand
Elasticsearch stores audit logs. Currently, anyone can access, modify, or delete these logs without authentication.

#### Fix

Edit `infrastructure/docker-compose.yml`:

```yaml
elasticsearch:
  environment:
    - discovery.type=single-node
    - xpack.security.enabled=true
    - xpack.security.enrollment.enabled=true
    - ELASTIC_PASSWORD=${ELASTICSEARCH_PASSWORD}
    - "ES_JAVA_OPTS=-Xms1g -Xmx1g"
```

Update Kibana:

```yaml
kibana:
  environment:
    - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    - ELASTICSEARCH_USERNAME=kibana_system
    - ELASTICSEARCH_PASSWORD=${ELASTICSEARCH_PASSWORD}
```

Update Logstash:

```yaml
logstash:
  environment:
    - ELASTICSEARCH_USERNAME=elastic
    - ELASTICSEARCH_PASSWORD=${ELASTICSEARCH_PASSWORD}
```

Update `infrastructure/logstash/pipeline/logstash.conf`:

```
output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "mifos-audit-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "${ELASTICSEARCH_PASSWORD}"
  }
}
```

#### Verify

```bash
# Restart ELK stack
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure
docker-compose down elasticsearch kibana logstash
docker-compose up -d elasticsearch

# Wait for Elasticsearch to start
sleep 60

# Test authentication required
curl http://localhost:9200
# Should return 401 Unauthorized

# Test with credentials
source ../.env
curl -u elastic:$ELASTICSEARCH_PASSWORD http://localhost:9200
# Should return cluster info

# Start Kibana and Logstash
docker-compose up -d kibana logstash
```

#### Integration Check

```bash
# Verify Kibana can access Elasticsearch
curl http://localhost:5601/api/status | jq '.status.overall.state'
# Should show "green" or "yellow"

# Verify audit logs are being created
curl -u elastic:$ELASTICSEARCH_PASSWORD http://localhost:9200/_cat/indices | grep mifos-audit
```

**CHECKPOINT: Elasticsearch requires authentication. Audit logs are secured. Do not proceed until verified.**

---

### Step 2.5: Enable Redis Authentication

#### Understand
Redis stores session data. Without authentication, anyone can read or modify sessions.

#### Fix

Edit `infrastructure/docker-compose.yml`:

```yaml
redis:
  command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
  healthcheck:
    test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
```

#### Verify

```bash
# Restart Redis
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure
docker-compose restart redis

# Test authentication required
docker exec -it mifos-redis redis-cli ping
# Should show: NOAUTH Authentication required

# Test with password
source ../.env
docker exec -it mifos-redis redis-cli -a $REDIS_PASSWORD ping
# Should show: PONG
```

#### Integration Check

```bash
# Verify Redis is healthy
docker ps | grep redis
# Should show "healthy"
```

**CHECKPOINT: Redis requires authentication. Do not proceed until verified.**

---

### Step 2.6: Enable Kafka SSL/SASL

#### Understand
Kafka transmits all events in plaintext. This includes transaction events and sensitive data.

#### Fix

```bash
# 1. Generate Kafka SSL certificates
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure
mkdir -p kafka/ssl
cd kafka/ssl

# Generate CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt -subj "/CN=Kafka-CA"

# Generate broker cert
openssl genrsa -out kafka.key 4096
openssl req -new -key kafka.key -out kafka.csr -subj "/CN=kafka"
openssl x509 -req -days 365 -in kafka.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kafka.crt

# Create PKCS12 keystore
openssl pkcs12 -export -in kafka.crt -inkey kafka.key -out kafka.p12 -name kafka -password pass:kafkapass

# Create JKS keystore (Kafka uses this)
keytool -importkeystore -deststorepass kafkapass -destkeypass kafkapass \
  -destkeystore kafka.keystore.jks -srckeystore kafka.p12 \
  -srcstoretype PKCS12 -srcstorepass kafkapass -alias kafka

# Create truststore
keytool -import -file ca.crt -alias ca -keystore kafka.truststore.jks \
  -storepass kafkapass -noprompt
```

Update `infrastructure/docker-compose.yml`:

```yaml
kafka:
  environment:
    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: SSL:SSL,SSL_HOST:SSL
    KAFKA_ADVERTISED_LISTENERS: SSL://kafka:9092,SSL_HOST://localhost:29092
    KAFKA_SSL_KEYSTORE_LOCATION: /etc/kafka/ssl/kafka.keystore.jks
    KAFKA_SSL_KEYSTORE_PASSWORD: kafkapass
    KAFKA_SSL_KEY_PASSWORD: kafkapass
    KAFKA_SSL_TRUSTSTORE_LOCATION: /etc/kafka/ssl/kafka.truststore.jks
    KAFKA_SSL_TRUSTSTORE_PASSWORD: kafkapass
    KAFKA_SSL_CLIENT_AUTH: required
  volumes:
    - ./kafka/ssl:/etc/kafka/ssl:ro
```

#### Verify

```bash
# Restart Kafka
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure
docker-compose restart kafka

# Wait for startup
sleep 30

# Check Kafka is running with SSL
docker logs mifos-kafka 2>&1 | grep -i ssl
```

#### Integration Check

```bash
# Verify Kafka UI can still connect (may need config update)
docker-compose restart kafka-ui

curl http://localhost:8090 | grep -i kafka
```

**CHECKPOINT: Kafka uses SSL. Do not proceed until verified.**

---

## Phase 3: Network Security

### Step 3.1: Remove External Database Port Mappings

#### Understand
All databases are currently accessible from any network. We need to remove external port mappings.

#### Fix

Edit each docker-compose.yml and change `ports` to `expose` for databases:

**mifosplatform/.../docker-compose.yml:**
```yaml
postgresql:
  # Remove this:
  # ports:
  #   - "5432:5432"
  # Add this:
  expose:
    - "5432"
```

**infrastructure/docker-compose.yml:**
```yaml
elasticsearch:
  expose:
    - "9200"
  # Remove ports mapping

redis:
  expose:
    - "6379"
  # Remove ports mapping

infra-mysql:
  expose:
    - "3306"
  # Remove ports mapping

keycloak-postgres:
  expose:
    - "5432"
  # Remove ports mapping
```

**payment-hub-ee/docker-compose.yml:**
```yaml
mysql:
  expose:
    - "3306"
  # Remove ports mapping
```

#### Verify

```bash
# Restart all services
./stop-all.sh
./start-all.sh

# Wait for startup
sleep 60

# Try to connect to PostgreSQL from host
psql -h localhost -p 5432 -U postgres
# Should fail: connection refused

# Try to connect to Redis from host
redis-cli -h localhost ping
# Should fail: connection refused
```

#### Integration Check

```bash
# Verify Fineract can still connect to PostgreSQL (internal network)
curl -k https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password

# Verify services are healthy
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -v "unhealthy"
```

**CHECKPOINT: Databases are not accessible from host. Services communicate internally. Do not proceed until verified.**

---

### Step 3.2: Implement Network Segmentation

#### Understand
All services are on one network. We need to separate them into tiers.

#### Fix

Create separate networks in `infrastructure/docker-compose.yml`:

```yaml
networks:
  dmz:
    name: mifos-dmz
    driver: bridge
  app:
    name: mifos-app
    driver: bridge
  data:
    name: mifos-data
    driver: bridge
  monitoring:
    name: mifos-monitoring
    driver: bridge
```

Assign services to appropriate networks:

```yaml
# DMZ (public-facing)
nginx:
  networks:
    - dmz
    - app

# App tier
keycloak:
  networks:
    - app
    - data

# Data tier
elasticsearch:
  networks:
    - data

redis:
  networks:
    - data

# Monitoring
prometheus:
  networks:
    - monitoring
    - app
    - data

grafana:
  networks:
    - monitoring
```

#### Verify

```bash
# Restart infrastructure
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure
docker-compose down
docker-compose up -d

# List networks
docker network ls | grep mifos
# Should show: mifos-dmz, mifos-app, mifos-data, mifos-monitoring
```

#### Integration Check

```bash
# Verify services can communicate within their tier
docker exec -it mifos-nginx ping elasticsearch
# Should fail (different networks)

docker exec -it mifos-prometheus ping elasticsearch
# Should succeed (both on data network)
```

**CHECKPOINT: Network segmentation implemented. Services isolated by tier. Do not proceed until verified.**

---

## Phase 4: Compliance Implementation

### Step 4.1: Configure Audit Log Retention (7 Years)

#### Understand
Banking regulations require 7-year retention of audit logs. Currently, no retention policy exists.

#### Fix

```bash
# Create Elasticsearch ILM policy
source .env

curl -X PUT "http://localhost:9200/_ilm/policy/mifos-audit-policy" \
  -u elastic:$ELASTICSEARCH_PASSWORD \
  -H "Content-Type: application/json" \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "actions": {
            "rollover": {
              "max_size": "50GB",
              "max_age": "30d"
            }
          }
        },
        "warm": {
          "min_age": "30d",
          "actions": {
            "shrink": {
              "number_of_shards": 1
            },
            "forcemerge": {
              "max_num_segments": 1
            }
          }
        },
        "cold": {
          "min_age": "90d",
          "actions": {
            "freeze": {}
          }
        },
        "delete": {
          "min_age": "2555d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'

# Apply policy to audit index template
curl -X PUT "http://localhost:9200/_index_template/mifos-audit-template" \
  -u elastic:$ELASTICSEARCH_PASSWORD \
  -H "Content-Type: application/json" \
  -d '{
    "index_patterns": ["mifos-audit-*"],
    "template": {
      "settings": {
        "index.lifecycle.name": "mifos-audit-policy",
        "index.lifecycle.rollover_alias": "mifos-audit",
        "number_of_shards": 1,
        "number_of_replicas": 1
      }
    }
  }'
```

#### Verify

```bash
# Check policy exists
curl -u elastic:$ELASTICSEARCH_PASSWORD http://localhost:9200/_ilm/policy/mifos-audit-policy

# Check template exists
curl -u elastic:$ELASTICSEARCH_PASSWORD http://localhost:9200/_index_template/mifos-audit-template
```

#### Integration Check

```bash
# Create a test log entry
curl -X POST "http://localhost:9200/mifos-audit-000001/_doc" \
  -u elastic:$ELASTICSEARCH_PASSWORD \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "action": "TEST_AUDIT_LOG",
    "user": "system",
    "details": "Testing audit log retention policy"
  }'

# Verify it was created
curl -u elastic:$ELASTICSEARCH_PASSWORD "http://localhost:9200/mifos-audit-*/_search?pretty"
```

**CHECKPOINT: 7-year audit retention policy configured. Do not proceed until verified.**

---

### Step 4.2: Integrate OFAC Screening as Mandatory

#### Understand
OFAC screening exists via Marble/Yente but is not mandatory in the transaction flow. We need to make it required.

#### Fix

This requires configuring the Payment Hub workflow to include OFAC check.

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup/payment-hub-ee/orchestration/bpmn
```

Create `ofac-screening.bpmn` workflow that:
1. Receives transaction request
2. Calls Marble API for OFAC check
3. If blocked → reject transaction
4. If clear → proceed to payment

**Note:** This is a complex integration that requires BPMN workflow development. The detailed implementation would be:

1. Create Zeebe workflow with OFAC check step
2. Configure Marble rules for OFAC screening
3. Connect Yente to OpenSanctions data
4. Set up webhook from Fineract to Payment Hub

#### Verify

```bash
# Verify Marble is running
curl http://localhost:3001/healthcheck

# Verify Yente (sanctions database) is running
curl http://localhost:8001/healthz
```

#### Integration Check

This requires end-to-end testing with a test transaction.

**CHECKPOINT: OFAC screening integrated (requires additional workflow development). Document current state and proceed.**

---

### Step 4.3: Implement CTR Tracking

#### Understand
Cash Transaction Reports (CTRs) are required for cash transactions over $10,000. We need automated tracking.

#### Fix

Create a Fineract hook that monitors transactions:

```bash
# This requires custom Fineract development or a monitoring service
# that watches for transactions > $10,000

# Basic approach using Logstash:
```

Add to `infrastructure/logstash/pipeline/logstash.conf`:

```
filter {
  if [transaction_type] == "deposit" or [transaction_type] == "withdrawal" {
    if [amount] >= 10000 {
      mutate {
        add_tag => ["ctr_required", "regulatory"]
        add_field => { "ctr_status" => "pending" }
      }
    }
  }
}

output {
  if "ctr_required" in [tags] {
    elasticsearch {
      hosts => ["http://elasticsearch:9200"]
      index => "mifos-ctr-%{+YYYY.MM.dd}"
      user => "elastic"
      password => "${ELASTICSEARCH_PASSWORD}"
    }
  }
}
```

#### Verify

```bash
# Restart Logstash
cd /Users/reeceway/Desktop/fineract-mifos-setup/infrastructure
docker-compose restart logstash

# Check CTR index exists after a qualifying transaction
curl -u elastic:$ELASTICSEARCH_PASSWORD http://localhost:9200/_cat/indices | grep ctr
```

#### Integration Check

```bash
# Simulate a large cash transaction and verify it's flagged
# (Requires Fineract transaction and proper event emission)
```

**CHECKPOINT: CTR tracking pipeline configured. Requires transaction testing. Do not proceed until verified.**

---

## Phase 5: High Availability

### Step 5.1: Deploy PostgreSQL Replication

#### Understand
Single database instance means any failure causes complete system outage. We need primary-replica setup.

#### Fix

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup/mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
```

Update `docker-compose.yml` to add replica:

```yaml
services:
  postgresql-primary:
    image: postgres:16.6
    container_name: mifos-pg-primary
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_USER=postgres
      - POSTGRES_DB=fineract_tenants
    volumes:
      - pg-primary-data:/var/lib/postgresql/data
    command: |
      postgres
      -c wal_level=replica
      -c max_wal_senders=3
      -c max_replication_slots=3
      -c hot_standby=on
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  postgresql-replica:
    image: postgres:16.6
    container_name: mifos-pg-replica
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_USER=postgres
      - PGUSER=postgres
      - PGPASSWORD=${POSTGRES_PASSWORD}
    depends_on:
      postgresql-primary:
        condition: service_healthy
    command: |
      bash -c "
      until pg_basebackup -h postgresql-primary -D /var/lib/postgresql/data -U postgres -Fp -Xs -P -R; do
        echo 'Waiting for primary...'
        sleep 5
      done
      postgres
      "
    volumes:
      - pg-replica-data:/var/lib/postgresql/data

volumes:
  pg-primary-data:
  pg-replica-data:
```

#### Verify

```bash
# Restart PostgreSQL
docker-compose down
docker-compose up -d

# Wait for replication to sync
sleep 60

# Check replication status on primary
docker exec -it mifos-pg-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"
# Should show connected replica
```

#### Integration Check

```bash
# Verify Fineract still works
curl -k https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password

# Verify data exists on replica
docker exec -it mifos-pg-replica psql -U postgres -d fineract_tenants -c "SELECT count(*) FROM m_office;"
```

**CHECKPOINT: PostgreSQL replication working. Primary and replica in sync. Do not proceed until verified.**

---

### Step 5.2: Deploy Fineract Cluster

#### Understand
Single Fineract instance means any failure causes complete API outage. We need multiple instances behind a load balancer.

#### Fix

Update `docker-compose.yml`:

```yaml
services:
  fineract-1:
    image: openmf/fineract:1.11
    container_name: mifos-fineract-1
    environment:
      - FINERACT_NODE_ID=1
      # ... other env vars
    expose:
      - "8443"

  fineract-2:
    image: openmf/fineract:1.11
    container_name: mifos-fineract-2
    environment:
      - FINERACT_NODE_ID=2
      # ... other env vars
    expose:
      - "8443"

  fineract-3:
    image: openmf/fineract:1.11
    container_name: mifos-fineract-3
    environment:
      - FINERACT_NODE_ID=3
      # ... other env vars
    expose:
      - "8443"

  haproxy:
    image: haproxy:2.8
    container_name: mifos-haproxy
    ports:
      - "8443:8443"
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - fineract-1
      - fineract-2
      - fineract-3
```

Create `haproxy.cfg`:

```
global
    log stdout format raw local0

defaults
    log global
    mode http
    option httplog
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend fineract_front
    bind *:8443 ssl crt /etc/haproxy/certs/fineract.pem
    default_backend fineract_back

backend fineract_back
    balance roundrobin
    option httpchk GET /fineract-provider/actuator/health
    server fineract1 fineract-1:8443 check ssl verify none
    server fineract2 fineract-2:8443 check ssl verify none
    server fineract3 fineract-3:8443 check ssl verify none
```

#### Verify

```bash
# Restart Fineract cluster
docker-compose down
docker-compose up -d

# Wait for all instances to start
sleep 90

# Check all instances are healthy
docker ps | grep fineract
# Should show 3 running instances

# Check HAProxy stats
curl http://localhost:8404/stats
```

#### Integration Check

```bash
# Make multiple requests, should be distributed
for i in {1..10}; do
  curl -k https://localhost:8443/fineract-provider/api/v1/offices \
    -H "Fineract-Platform-TenantId: default" \
    -u mifos:password -s | jq '.[0].name'
done
# All should return "Head Office"

# Stop one instance and verify still works
docker stop mifos-fineract-1

curl -k https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password
# Should still work (routed to fineract-2 or fineract-3)

# Restart the instance
docker start mifos-fineract-1
```

**CHECKPOINT: Fineract cluster with 3 nodes. Load balanced. Failover working. Do not proceed until verified.**

---

## Phase 6: Final Verification

### Step 6.1: Full System Integration Test

#### Understand
We need to verify the entire system works together after all changes.

#### Fix

Run complete test sequence:

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup

# 1. Stop everything
./stop-all.sh

# 2. Start everything
./start-all.sh

# 3. Wait for all services
sleep 120
```

#### Verify

```bash
# Check all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -c "Up"
# Should match expected container count

# Check no containers are unhealthy
docker ps | grep -c "unhealthy"
# Should be 0
```

#### Integration Check

Run complete test script:

```bash
#!/bin/bash
echo "=== FULL SYSTEM INTEGRATION TEST ==="

echo "1. Testing Fineract API (HTTPS)..."
curl -k https://localhost:8443/fineract-provider/api/v1/offices \
  -H "Fineract-Platform-TenantId: default" \
  -u mifos:password -s | jq '.[0].name'

echo "2. Testing Staff Portal..."
curl -s http://localhost | grep -c "mifos"

echo "3. Testing Customer Portal..."
curl -s http://localhost:4200 | grep -c "html"

echo "4. Testing Marble Compliance..."
curl -s http://localhost:3001/healthcheck

echo "5. Testing Moov ACH..."
curl -s http://localhost:8200/files 2>/dev/null || echo "OK (empty)"

echo "6. Testing Elasticsearch (authenticated)..."
source .env
curl -s -u elastic:$ELASTICSEARCH_PASSWORD http://localhost:9200 | jq '.cluster_name'

echo "7. Testing Keycloak..."
curl -s http://localhost:8180/health/ready

echo "8. Testing Grafana..."
curl -s http://localhost:3000/api/health | jq '.database'

echo "9. Testing Vault..."
curl -sk https://localhost:8200/v1/sys/health | jq '.sealed'

echo "=== ALL TESTS COMPLETE ==="
```

**CHECKPOINT: All systems integrated and working. Full test passed. System ready for security audit.**

---

## Post-Remediation Checklist

### Before Production Deployment

- [ ] All hardcoded passwords removed
- [ ] All services use environment variables
- [ ] SSL/TLS enabled on all services
- [ ] Database ports not exposed externally
- [ ] Network segmentation implemented
- [ ] 7-year audit retention configured
- [ ] High availability deployed
- [ ] Backup procedures tested
- [ ] Penetration test completed
- [ ] Compliance audit passed

### Documentation Updated

- [ ] README.md updated with new architecture
- [ ] .env.example created (no real values)
- [ ] Runbooks created for operations
- [ ] Disaster recovery procedures documented

### Monitoring Verified

- [ ] All services have health checks
- [ ] Alerting configured for failures
- [ ] Dashboards show system health
- [ ] Audit logs flowing to Elasticsearch

---

## Summary

This guide takes you from the current 16% compliance score to production-ready by:

1. **Phase 1** - Securing all credentials in Vault
2. **Phase 2** - Enabling SSL/TLS everywhere
3. **Phase 3** - Isolating networks properly
4. **Phase 4** - Implementing regulatory compliance
5. **Phase 5** - Deploying high availability
6. **Phase 6** - Verifying complete integration

Each step includes verification before moving on, ensuring nothing breaks as you progress.