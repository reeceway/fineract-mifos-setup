# Production Readiness Checklist

## Current Score: 65% → Target: 100%

This checklist covers the remaining items needed for full production deployment and regulatory compliance.

**Created:** 2026-01-14

---

## Phase 5: TLS/Encryption Hardening (65% → 75%)

### 5.1 Internal Service TLS
| # | Task | Service | Priority | Status |
|---|------|---------|----------|--------|
| 1 | Enable Kafka TLS (SASL_SSL) | Kafka | HIGH | ⬜ PENDING |
| 2 | Enable Redis TLS | Redis | HIGH | ⬜ PENDING |
| 3 | Enable PostgreSQL SSL mode | PostgreSQL | HIGH | ⬜ PENDING |
| 4 | Enable MySQL SSL mode | MySQL | HIGH | ⬜ PENDING |
| 5 | Enable Zeebe TLS | Payment Hub | MEDIUM | ⬜ PENDING |
| 6 | Enable Elasticsearch HTTPS | Elasticsearch | MEDIUM | ⬜ PENDING |
| 7 | Replace self-signed certs with CA-signed | All | HIGH | ⬜ PENDING |

### 5.2 Certificate Management
| # | Task | Details | Status |
|---|------|---------|--------|
| 8 | Obtain CA-signed wildcard cert | *.yourdomain.com | ⬜ PENDING |
| 9 | Configure cert auto-renewal | Let's Encrypt or internal CA | ⬜ PENDING |
| 10 | Set up certificate monitoring | Alert on expiry < 30 days | ⬜ PENDING |
| 11 | Store certs in Vault | HashiCorp Vault PKI | ⬜ PENDING |

---

## Phase 6: High Availability (75% → 85%)

### 6.1 Database HA
| # | Task | Configuration | Status |
|---|------|---------------|--------|
| 12 | PostgreSQL Primary-Replica | 1 primary + 2 replicas | ⬜ PENDING |
| 13 | PostgreSQL connection pooling | PgBouncer | ⬜ PENDING |
| 14 | MySQL Primary-Replica | 1 primary + 1 replica | ⬜ PENDING |
| 15 | Automatic failover | Patroni for PostgreSQL | ⬜ PENDING |

### 6.2 Application HA
| # | Task | Configuration | Status |
|---|------|---------------|--------|
| 16 | Fineract multiple instances | 2+ instances behind LB | ⬜ PENDING |
| 17 | Payment Hub Channel HA | 2+ instances | ⬜ PENDING |
| 18 | Marble API HA | 2+ instances | ⬜ PENDING |
| 19 | Load balancer health checks | Active health probes | ⬜ PENDING |

### 6.3 Infrastructure HA
| # | Task | Configuration | Status |
|---|------|---------------|--------|
| 20 | Elasticsearch cluster | 3 nodes minimum | ⬜ PENDING |
| 21 | Kafka cluster | 3 brokers minimum | ⬜ PENDING |
| 22 | Redis Sentinel/Cluster | 3 nodes with Sentinel | ⬜ PENDING |
| 23 | Zeebe cluster | 3 brokers | ⬜ PENDING |
| 24 | Keycloak cluster | 2+ instances | ⬜ PENDING |

---

## Phase 7: Disaster Recovery (85% → 90%)

### 7.1 Backup Configuration
| # | Task | Schedule | Retention | Status |
|---|------|----------|-----------|--------|
| 25 | PostgreSQL automated backups | Every 6 hours | 30 days | ⬜ PENDING |
| 26 | MySQL automated backups | Every 6 hours | 30 days | ⬜ PENDING |
| 27 | Elasticsearch snapshots | Daily | 90 days | ⬜ PENDING |
| 28 | MinIO bucket replication | Real-time | - | ⬜ PENDING |
| 29 | Kafka topic backups | Daily | 7 days | ⬜ PENDING |
| 30 | Vault backup | Daily | 30 days | ⬜ PENDING |

### 7.2 Backup Security
| # | Task | Details | Status |
|---|------|---------|--------|
| 31 | Encrypt backups at rest | AES-256 | ⬜ PENDING |
| 32 | Encrypt backups in transit | TLS 1.3 | ⬜ PENDING |
| 33 | Off-site backup storage | Different region/cloud | ⬜ PENDING |
| 34 | Backup integrity verification | Daily checksum validation | ⬜ PENDING |

### 7.3 Recovery Procedures
| # | Task | Target | Status |
|---|------|--------|--------|
| 35 | Define RTO (Recovery Time Objective) | < 4 hours | ⬜ PENDING |
| 36 | Define RPO (Recovery Point Objective) | < 1 hour | ⬜ PENDING |
| 37 | Document recovery procedures | Runbooks | ⬜ PENDING |
| 38 | Test recovery quarterly | DR drill | ⬜ PENDING |
| 39 | Geographic replication | Multi-region | ⬜ PENDING |

---

## Phase 8: Security Hardening (90% → 95%)

### 8.1 Authentication & Access
| # | Task | Details | Status |
|---|------|---------|--------|
| 40 | Enable MFA in Keycloak | TOTP/WebAuthn | ⬜ PENDING |
| 41 | Configure password policies | 12+ chars, complexity | ⬜ PENDING |
| 42 | Session timeout configuration | 30 min idle, 8 hr max | ⬜ PENDING |
| 43 | API key rotation policy | 90 days | ⬜ PENDING |
| 44 | Service account audit | Remove unused | ⬜ PENDING |

### 8.2 Network Security
| # | Task | Details | Status |
|---|------|---------|--------|
| 45 | Deploy WAF | ModSecurity/CloudFlare | ⬜ PENDING |
| 46 | Enable DDoS protection | Rate limiting + CDN | ⬜ PENDING |
| 47 | API rate limiting | 100 req/min per client | ⬜ PENDING |
| 48 | IP allowlisting for admin | VPN/specific IPs only | ⬜ PENDING |
| 49 | Network intrusion detection | Suricata/Snort | ⬜ PENDING |

### 8.3 Container Security
| # | Task | Details | Status |
|---|------|---------|--------|
| 50 | Run containers as non-root | All services | ⬜ PENDING |
| 51 | Enable seccomp profiles | Default Docker profile | ⬜ PENDING |
| 52 | Read-only root filesystem | Where possible | ⬜ PENDING |
| 53 | Image vulnerability scanning | Trivy/Clair in CI/CD | ⬜ PENDING |
| 54 | Container runtime security | Falco | ⬜ PENDING |

---

## Phase 9: Regulatory Compliance (95% → 100%)

### 9.1 BSA/AML Automation
| # | Task | Regulation | Status |
|---|------|------------|--------|
| 55 | CTR auto-generation | BSA (>$10k cash) | ⬜ PENDING |
| 56 | SAR workflow integration | BSA | ⬜ PENDING |
| 57 | OFAC real-time screening | OFAC | ⬜ PENDING |
| 58 | PEP screening | AML | ⬜ PENDING |
| 59 | Beneficial ownership tracking | CDD Rule | ⬜ PENDING |
| 60 | Transaction velocity monitoring | AML | ⬜ PENDING |

### 9.2 Audit & Compliance
| # | Task | Requirement | Status |
|---|------|-------------|--------|
| 61 | 7-year log retention | GLBA/BSA | ⬜ PENDING |
| 62 | Immutable audit logs | SOX/GLBA | ⬜ PENDING |
| 63 | Log tamper detection | Checksums/blockchain | ⬜ PENDING |
| 64 | SIEM integration | Security monitoring | ⬜ PENDING |
| 65 | Compliance reporting dashboard | Examiner-ready | ⬜ PENDING |

### 9.3 Monitoring & Alerting
| # | Task | Details | Status |
|---|------|---------|--------|
| 66 | Grafana alert rules | Critical service alerts | ⬜ PENDING |
| 67 | PagerDuty/OpsGenie integration | On-call rotation | ⬜ PENDING |
| 68 | SLA monitoring dashboards | 99.9% uptime tracking | ⬜ PENDING |
| 69 | Anomaly detection | ML-based monitoring | ⬜ PENDING |
| 70 | Executive compliance dashboard | Board reporting | ⬜ PENDING |

---

## Implementation Guides

### 5.1 Kafka TLS Configuration

```yaml
# infrastructure/docker-compose.yml - Kafka TLS
kafka:
  environment:
    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:SSL,EXTERNAL:SSL
    KAFKA_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.keystore.jks
    KAFKA_SSL_KEYSTORE_PASSWORD: ${KAFKA_SSL_PASSWORD}
    KAFKA_SSL_KEY_PASSWORD: ${KAFKA_SSL_PASSWORD}
    KAFKA_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.truststore.jks
    KAFKA_SSL_TRUSTSTORE_PASSWORD: ${KAFKA_SSL_PASSWORD}
    KAFKA_SSL_CLIENT_AUTH: required
  volumes:
    - ./ssl/kafka:/etc/kafka/secrets:ro
```

### 5.2 Redis TLS Configuration

```yaml
# infrastructure/docker-compose.yml - Redis TLS
redis:
  command: >
    redis-server
    --appendonly yes
    --requirepass ${REDIS_PASSWORD}
    --tls-port 6379
    --port 0
    --tls-cert-file /tls/redis.crt
    --tls-key-file /tls/redis.key
    --tls-ca-cert-file /tls/ca.crt
  volumes:
    - ./ssl/redis:/tls:ro
```

### 5.3 PostgreSQL SSL Configuration

```yaml
# Add to PostgreSQL service
postgresql:
  command: >
    -c ssl=on
    -c ssl_cert_file=/var/lib/postgresql/server.crt
    -c ssl_key_file=/var/lib/postgresql/server.key
    -c ssl_ca_file=/var/lib/postgresql/ca.crt
  volumes:
    - ./ssl/postgres:/var/lib/postgresql:ro
```

### 6.1 PostgreSQL HA with Patroni

```yaml
# docker-compose.ha.yml
services:
  postgres-1:
    image: postgres:15-alpine
    environment:
      PATRONI_NAME: postgres-1
      PATRONI_POSTGRESQL_CONNECT_ADDRESS: postgres-1:5432

  postgres-2:
    image: postgres:15-alpine
    environment:
      PATRONI_NAME: postgres-2
      PATRONI_POSTGRESQL_CONNECT_ADDRESS: postgres-2:5432

  postgres-3:
    image: postgres:15-alpine
    environment:
      PATRONI_NAME: postgres-3
      PATRONI_POSTGRESQL_CONNECT_ADDRESS: postgres-3:5432

  haproxy:
    image: haproxy:2.8
    ports:
      - "5432:5432"
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
```

### 7.1 Automated Backup Script

```bash
#!/bin/bash
# scripts/backup.sh

BACKUP_DIR="/backups/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# PostgreSQL backup
docker exec mifosx-postgresql-postgresql-1 \
  pg_dumpall -U postgres | \
  gzip | \
  openssl enc -aes-256-cbc -salt -pass env:BACKUP_PASSWORD \
  > $BACKUP_DIR/postgres.sql.gz.enc

# MySQL backup
docker exec ph-mysql \
  mysqldump -u root -p${PH_MYSQL_ROOT_PASSWORD} --all-databases | \
  gzip | \
  openssl enc -aes-256-cbc -salt -pass env:BACKUP_PASSWORD \
  > $BACKUP_DIR/mysql.sql.gz.enc

# Elasticsearch snapshot
curl -X PUT "localhost:9200/_snapshot/backup_repo/snapshot_$(date +%Y%m%d)" \
  -H 'Content-Type: application/json' \
  -u elastic:${ELASTICSEARCH_PASSWORD}

# Upload to S3/off-site
aws s3 sync $BACKUP_DIR s3://your-backup-bucket/$(date +%Y%m%d)/
```

### 8.1 Keycloak MFA Configuration

```bash
# Enable TOTP for realm
curl -X PUT "http://localhost:8181/admin/realms/mifos" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "otpPolicyType": "totp",
    "otpPolicyAlgorithm": "HmacSHA256",
    "otpPolicyInitialCounter": 0,
    "otpPolicyDigits": 6,
    "otpPolicyLookAheadWindow": 1,
    "otpPolicyPeriod": 30
  }'

# Require MFA for all users
curl -X POST "http://localhost:8181/admin/realms/mifos/authentication/required-actions/CONFIGURE_TOTP" \
  -H "Authorization: Bearer $TOKEN"
```

### 9.1 Elasticsearch 7-Year Retention (ILM Policy)

```bash
# Create ILM policy for audit logs
curl -X PUT "localhost:9200/_ilm/policy/audit-retention" \
  -H 'Content-Type: application/json' \
  -u elastic:${ELASTICSEARCH_PASSWORD} \
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
            "shrink": { "number_of_shards": 1 },
            "forcemerge": { "max_num_segments": 1 }
          }
        },
        "cold": {
          "min_age": "90d",
          "actions": {
            "searchable_snapshot": {
              "snapshot_repository": "audit-archive"
            }
          }
        },
        "delete": {
          "min_age": "2557d",
          "actions": { "delete": {} }
        }
      }
    }
  }'
```

### 9.2 Grafana Alert Rules

```yaml
# grafana/provisioning/alerting/alerts.yml
groups:
  - name: Critical Alerts
    rules:
      - alert: FineractDown
        expr: up{job="fineract"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Fineract server is down"

      - alert: DatabaseConnectionHigh
        expr: pg_stat_activity_count > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High database connections"

      - alert: TransactionFailureRate
        expr: rate(transaction_failures_total[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Transaction failure rate > 1%"

      - alert: SuspiciousActivityDetected
        expr: marble_alerts_total{severity="high"} > 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "BSA/AML alert triggered"
```

---

## Priority Order

### Week 1: TLS Hardening (Items 1-11)
1. Generate CA-signed certificates
2. Enable PostgreSQL SSL
3. Enable MySQL SSL
4. Enable Redis TLS
5. Enable Kafka TLS
6. Store all certs in Vault

### Week 2: MFA & Security (Items 40-49)
1. Configure Keycloak MFA
2. Set password policies
3. Configure session management
4. Deploy WAF
5. Enable rate limiting

### Week 3: Backup & DR (Items 25-39)
1. Set up automated backups
2. Configure backup encryption
3. Set up off-site storage
4. Document recovery procedures
5. Run first DR drill

### Week 4: HA Infrastructure (Items 12-24)
1. Deploy PostgreSQL cluster
2. Deploy Elasticsearch cluster
3. Deploy Kafka cluster
4. Configure load balancers
5. Test failover

### Week 5: Regulatory Compliance (Items 55-70)
1. Configure BSA/AML rules in Marble
2. Set up 7-year retention
3. Configure SIEM integration
4. Build compliance dashboards
5. Document for examiners

---

## Estimated Effort

| Phase | Items | Estimated Days | Team Required |
|-------|-------|----------------|---------------|
| TLS Hardening | 11 | 3-5 days | DevOps |
| High Availability | 13 | 10-15 days | DevOps + DBA |
| Disaster Recovery | 15 | 5-7 days | DevOps |
| Security Hardening | 15 | 5-7 days | Security + DevOps |
| Regulatory Compliance | 16 | 10-14 days | Compliance + Dev |
| **Total** | **70** | **33-48 days** | |

---

## Compliance Mapping

| Regulation | Items Required | Current Status |
|------------|----------------|----------------|
| **GLBA** | 7, 31-34, 61-63 | 40% |
| **BSA/AML** | 55-60 | 60% |
| **SOX** | 61-65 | 30% |
| **PCI-DSS** | 1-7, 40-54 | 50% |
| **FFIEC** | All | 65% |

---

## Sign-Off Requirements

Before going to production, obtain sign-off from:

- [ ] **CISO** - Security controls
- [ ] **Compliance Officer** - Regulatory requirements
- [ ] **DBA** - Database HA/DR
- [ ] **DevOps Lead** - Infrastructure readiness
- [ ] **External Auditor** - Independent assessment
- [ ] **Legal** - Data privacy compliance

---

## Quick Commands

```bash
# Check current TLS status
./scripts/check-tls-status.sh

# Run security scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image openmf/fineract:1.11

# Test backup restoration
./scripts/test-backup-restore.sh

# Generate compliance report
./scripts/generate-compliance-report.sh
```
