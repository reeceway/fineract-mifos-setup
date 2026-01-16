# Disaster Recovery Runbook

## MifosBank Production Environment

**Version:** 1.0
**Last Updated:** 2026-01-15
**Owner:** IT Operations

---

## Table of Contents

1. [Overview](#overview)
2. [Recovery Objectives](#recovery-objectives)
3. [Contact Information](#contact-information)
4. [Backup Information](#backup-information)
5. [Recovery Procedures](#recovery-procedures)
6. [Verification Checklist](#verification-checklist)
7. [Escalation Procedures](#escalation-procedures)

---

## Overview

This runbook provides step-by-step procedures for recovering the MifosBank banking platform in the event of a disaster. Follow these procedures in order to restore services.

### Covered Systems

| System | Type | RTO | RPO |
|--------|------|-----|-----|
| PostgreSQL (Fineract) | Database | 2 hours | 6 hours |
| MySQL (Infrastructure) | Database | 2 hours | 6 hours |
| Elasticsearch | Search/Audit | 4 hours | 24 hours |
| HashiCorp Vault | Secrets | 1 hour | 24 hours |
| Keycloak | Identity | 2 hours | 24 hours |
| Application Containers | Services | 30 min | N/A |

---

## Recovery Objectives

### RTO (Recovery Time Objective): < 4 hours
Maximum acceptable time to restore services after a disaster.

### RPO (Recovery Point Objective): < 6 hours
Maximum acceptable data loss measured in time (databases are backed up every 6 hours).

---

## Contact Information

| Role | Name | Phone | Email |
|------|------|-------|-------|
| IT Operations Lead | [Name] | [Phone] | [Email] |
| Database Admin | [Name] | [Phone] | [Email] |
| Security Team | [Name] | [Phone] | [Email] |
| Vendor Support | Mifos | N/A | community@mifos.org |

---

## Backup Information

### Backup Locations

| Type | Location | Retention |
|------|----------|-----------|
| PostgreSQL | `/backups/postgres/` | 30 days |
| MySQL | `/backups/mysql/` | 30 days |
| Elasticsearch | ES Repository `backup_repo` | 90 days |
| Vault | `/backups/vault/` | 30 days |
| Off-site (S3) | `s3://your-backup-bucket/` | 90 days |

### Backup Schedule

| System | Frequency | Time |
|--------|-----------|------|
| PostgreSQL | Every 6 hours | 00:00, 06:00, 12:00, 18:00 |
| MySQL | Every 6 hours | 00:15, 06:15, 12:15, 18:15 |
| Elasticsearch | Daily | 02:00 |
| Vault | Daily | 02:30 |

### Backup Encryption

All backups are encrypted with AES-256. The encryption key is stored in:
- HashiCorp Vault: `secret/backup/encryption-key`
- Emergency: Physical safe (backup key on USB)

---

## Recovery Procedures

### Pre-Recovery Checklist

- [ ] Confirm disaster declaration and authorization
- [ ] Notify stakeholders
- [ ] Gather recovery team
- [ ] Verify access to backup storage
- [ ] Obtain encryption keys
- [ ] Prepare recovery environment

---

### Procedure 1: Full Environment Recovery

**Use when:** Complete infrastructure failure, need to rebuild from scratch.

#### Step 1.1: Prepare Infrastructure

```bash
# Clone repository
git clone https://github.com/your-org/fineract-mifos-setup.git
cd fineract-mifos-setup

# Copy environment file
cp .env.backup.latest .env
# Edit .env with production values

# Create Docker networks
docker network create mifos-app
docker network create mifos-fineract-network
```

#### Step 1.2: Restore SSL Certificates

```bash
# Restore certificates from Vault backup or regenerate
./ssl/generate-certs.sh

# Or restore from backup
tar -xzf /backups/ssl/ssl_backup_latest.tar.gz -C ./ssl/
```

#### Step 1.3: Start Infrastructure Services

```bash
# Start infrastructure containers
cd infrastructure
docker-compose up -d keycloak-postgres keycloak
docker-compose up -d zookeeper kafka
docker-compose up -d elasticsearch
docker-compose up -d redis vault minio
docker-compose up -d nginx prometheus grafana
```

#### Step 1.4: Start Database Services

```bash
# Start PostgreSQL (Fineract)
cd ../mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
docker-compose up -d postgresql
```

#### Step 1.5: Restore Databases

```bash
# Restore PostgreSQL
./scripts/restore/restore-postgres.sh /backups/postgres/postgres_backup_LATEST.sql.gz.enc

# Restore MySQL (both containers)
./scripts/restore/restore-mysql.sh /backups/mysql/mysql_backup_LATEST_infra-mysql.sql.gz.enc infra-mysql
./scripts/restore/restore-mysql.sh /backups/mysql/mysql_backup_LATEST_ph-mysql.sql.gz.enc ph-mysql
```

#### Step 1.6: Start Application Services

```bash
# Start Fineract
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
docker-compose up -d fineract-server web-app

# Start Payment Hub
cd ../../../payment-hub-ee
docker-compose up -d
```

#### Step 1.7: Restore Elasticsearch

```bash
# Restore from snapshot
curl -X POST "localhost:9200/_snapshot/backup_repo/SNAPSHOT_NAME/_restore" \
  -H "Content-Type: application/json" \
  -u elastic:$ELASTICSEARCH_PASSWORD \
  -d '{
    "indices": "*",
    "include_global_state": true
  }'
```

---

### Procedure 2: Database-Only Recovery

**Use when:** Database corruption, accidental data deletion.

#### PostgreSQL Recovery

```bash
# 1. Stop dependent services
docker stop fineract-server web-app

# 2. Verify current backup
./scripts/backup/verify-backups.sh

# 3. Restore database
./scripts/restore/restore-postgres.sh

# 4. Restart services
docker start fineract-server web-app

# 5. Verify functionality
curl -k https://localhost:8443/fineract-provider/api/v1/health
```

#### MySQL Recovery

```bash
# 1. Stop dependent services
docker stop message-gateway ph-channel

# 2. Restore database
./scripts/restore/restore-mysql.sh /backups/mysql/BACKUP_FILE.sql.gz.enc infra-mysql

# 3. Restart services
docker start message-gateway ph-channel
```

---

### Procedure 3: Single Service Recovery

**Use when:** Individual service failure.

#### Keycloak Recovery

```bash
# 1. Restore Keycloak database
docker exec keycloak-postgres psql -U keycloak -c "DROP DATABASE keycloak; CREATE DATABASE keycloak;"
docker exec -i keycloak-postgres psql -U keycloak keycloak < /backups/keycloak/keycloak_db.sql

# 2. Restart Keycloak
docker restart mifos-keycloak

# 3. Verify MFA configuration
curl http://localhost:8181/realms/mifos
```

#### Elasticsearch Recovery

```bash
# 1. List available snapshots
curl -s -u elastic:$ELASTICSEARCH_PASSWORD \
  "localhost:9200/_snapshot/backup_repo/_all" | jq '.snapshots[].snapshot'

# 2. Close indices
curl -X POST "localhost:9200/_all/_close" -u elastic:$ELASTICSEARCH_PASSWORD

# 3. Restore snapshot
curl -X POST "localhost:9200/_snapshot/backup_repo/SNAPSHOT_NAME/_restore" \
  -u elastic:$ELASTICSEARCH_PASSWORD \
  -H "Content-Type: application/json" \
  -d '{"indices": "*"}'
```

---

## Verification Checklist

After recovery, verify each system:

### Core Services

- [ ] PostgreSQL: `docker exec postgresql pg_isready`
- [ ] MySQL: `docker exec infra-mysql mysqladmin ping`
- [ ] Elasticsearch: `curl localhost:9200/_cluster/health`
- [ ] Redis: `docker exec redis redis-cli ping`
- [ ] Kafka: `docker logs mifos-kafka | grep "started"`

### Application Services

- [ ] Fineract API: `curl -k https://localhost:8443/fineract-provider/api/v1/health`
- [ ] Keycloak: `curl http://localhost:8181/realms/mifos`
- [ ] Web App: `curl http://localhost:80`

### Security Verification

- [ ] SSL certificates valid: `openssl s_client -connect localhost:443`
- [ ] Keycloak MFA enabled: Check realm settings
- [ ] Rate limiting active: Test API endpoints
- [ ] Audit logging working: Check Elasticsearch indices

### Data Verification

- [ ] Sample account lookup works
- [ ] Transaction history accessible
- [ ] User authentication working
- [ ] Reports generating correctly

---

## Escalation Procedures

### Severity Levels

| Level | Description | Response Time | Notification |
|-------|-------------|---------------|--------------|
| P1 | Complete outage | Immediate | All stakeholders |
| P2 | Partial outage | 30 minutes | IT + Management |
| P3 | Degraded service | 2 hours | IT Team |
| P4 | Minor issue | 24 hours | IT Team |

### Escalation Matrix

1. **First 30 minutes:** IT Operations attempt recovery
2. **30-60 minutes:** Escalate to Database Admin + Security
3. **1-2 hours:** Escalate to IT Management
4. **2+ hours:** Escalate to Executive Management

---

## Appendix

### A. Environment Variables Required

```bash
# Database passwords
POSTGRES_PASSWORD=
MYSQL_PASSWORD=
PH_MYSQL_ROOT_PASSWORD=

# Service credentials
KEYCLOAK_ADMIN_PASSWORD=
ELASTICSEARCH_PASSWORD=
REDIS_PASSWORD=
VAULT_DEV_ROOT_TOKEN_ID=

# Backup encryption
BACKUP_ENCRYPTION_KEY=
```

### B. Important File Locations

| File | Purpose |
|------|---------|
| `/.env` | Environment configuration |
| `/ssl/` | SSL certificates |
| `/backups/` | Backup storage |
| `/scripts/backup/` | Backup scripts |
| `/scripts/restore/` | Restore scripts |

### C. Recovery Time Estimates

| Component | Estimated Time |
|-----------|----------------|
| Infrastructure start | 10-15 min |
| Database restore (10GB) | 30-45 min |
| Elasticsearch restore | 30-60 min |
| Full verification | 30 min |
| **Total** | **2-3 hours** |

---

**Document Control:**
- Review quarterly
- Update after every DR drill
- Notify team of changes
