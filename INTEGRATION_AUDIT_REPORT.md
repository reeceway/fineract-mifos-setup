# Integration Architecture Audit Report
## Multi-Stakeholder Analysis: How Components Are Connected

**Audit Date:** January 2026
**Scope:** Integration layer ONLY (not underlying software)
**Focus:** Configuration decisions, service connections, data flows
**Classification:** CONFIDENTIAL

---

## Auditor Perspectives

| Role | Primary Concerns |
|------|------------------|
| **Regulatory Auditor** | Compliance gaps, audit trails, data sovereignty |
| **Security Specialist** | Attack surface, authentication flows, encryption |
| **Banking Executive** | Operational risk, vendor lock-in, business continuity |
| **Venture Investor** | Scalability, technical debt, regulatory exposure |

---

# SECTION 1: REGULATORY AUDITOR FINDINGS

## 1.1 BSA/AML Integration Gaps

### CRITICAL: No Enforced Compliance Checkpoint

**Finding:** Marble compliance engine is deployed but NOT integrated into the payment flow.

**Evidence:**
```yaml
# payment-hub-ee/docker-compose.yml
ams-mifos:
  environment:
    - FINERACT_BASE_URL=https://fineract-server:8443
    # NO MARBLE_API_URL configured
    # NO pre-transaction screening
```

**Issue:** Transactions can flow directly from Payment Hub → Fineract without OFAC/sanctions screening.

**Regulatory Violation:**
- 31 CFR 1010.610 (OFAC sanctions compliance)
- BSA Section 352 (AML program requirements)
- FinCEN CDD Rule (beneficial ownership)

**Required Fix:**
```yaml
# MUST add to ams-mifos connector
- MARBLE_API_URL=http://marble-api:8180
- SCREENING_ENABLED=true
- BLOCK_ON_MATCH=true
```

### HIGH: CTR Filing Not Automated

**Finding:** Logstash tags transactions >$10,000 but no FinCEN filing integration exists.

**Evidence:**
```ruby
# infrastructure/logstash/pipeline/logstash.conf (lines 38-42)
if [amount] and [amount] >= 10000 {
  mutate {
    add_tag => ["ctr_candidate", "large_transaction"]
  }
}
```

**Gap:** Tagged transactions go to Elasticsearch but:
- No automated CTR form generation
- No FinCEN BSA E-Filing integration
- No 15-day filing deadline tracking
- No aggregation logic for structuring detection

**Required:** Integration with FinCEN E-File system or third-party CTR service.

---

## 1.2 Audit Trail Deficiencies

### MEDIUM: Incomplete Transaction Lineage

**Finding:** No end-to-end correlation ID across all services.

**Data Flow Gap:**
```
Customer Portal → Fineract → Payment Hub → Marble → Moov
     ???           UUID-A      UUID-B       ???      UUID-C
```

**Issue:** If a wire transfer fails at Moov, tracing back to original customer request requires manual log correlation across 4 systems.

**Required:** Implement OpenTelemetry or similar distributed tracing with:
- Correlation ID passed in HTTP headers
- Span context propagation
- Centralized trace collection

### HIGH: Log Retention Non-Compliant

**Finding:** Prometheus retention is 90 days, but BSA requires 5 years.

**Evidence:**
```yaml
# infrastructure/docker-compose.yml (line 426)
- '--storage.tsdb.retention.time=90d'
```

**Regulatory Requirement:**
- BSA: 5 years for all transaction records
- SAR: 5 years from filing date
- OFAC: Indefinite for blocked transactions

**Required:**
- Elasticsearch: Set ILM policy for 5-year retention
- Archive to cold storage (S3 Glacier or equivalent)
- Implement immutable audit logs

---

## 1.3 Data Sovereignty Concerns

### MEDIUM: No Geographic Data Control

**Finding:** Docker images pulled from public registries with no control over data processing location.

**Evidence:**
```yaml
# Various docker-compose files
image: openmf/fineract:1.11           # DockerHub (US)
image: moov/ach:v1.33.5               # DockerHub (US)
image: docker.elastic.co/...          # Elastic (Netherlands)
image: quay.io/keycloak/keycloak:23.0 # Red Hat (US)
```

**Issue for international operations:**
- GDPR data residency requirements
- No guarantee images don't phone home
- Container registries may log pull metadata

**Recommendation:** Mirror images to private registry (Harbor, ECR, GCR).

---

# SECTION 2: SECURITY SPECIALIST FINDINGS

## 2.1 Authentication Architecture Weaknesses

### CRITICAL: Service-to-Service Auth Inconsistent

| Connection | Auth Method | Encrypted | Verdict |
|------------|-------------|-----------|---------|
| Nginx → Fineract | None (trusted network) | HTTPS | ⚠️ ACCEPTABLE |
| Payment Hub → Fineract | HTTP Basic | HTTPS | ⚠️ WEAK |
| Payment Hub → Zeebe | None | Plaintext | ❌ CRITICAL |
| Logstash → Elasticsearch | Password | HTTP | ❌ HIGH |
| Channel → Zeebe | None (gRPC) | Plaintext | ❌ CRITICAL |
| Marble → Yente | None | HTTP | ⚠️ MEDIUM |

**Critical Issue: Zeebe has no authentication**
```yaml
# payment-hub-ee/docker-compose.yml
zeebe:
  environment:
    - ZEEBE_BROKER_GATEWAY_SECURITY_ENABLED=false
```

**Attack Vector:** Any container in `ph-internal` network can:
- Submit fraudulent workflows
- Cancel legitimate transactions
- Extract workflow data
- Deploy malicious BPMN processes

**Required:** Enable Zeebe authentication with mTLS.

### HIGH: Basic Auth Credentials in Environment

**Finding:** Fineract credentials stored as plaintext environment variables.

```yaml
# payment-hub-ee/docker-compose.yml (lines 156-157)
ams-mifos:
  environment:
    - FINERACT_USERNAME=${FINERACT_USERNAME:-mifos}
    - FINERACT_PASSWORD=${FINERACT_PASSWORD}
```

**Issue:**
- Visible in `docker inspect`
- Logged in container startup
- No rotation mechanism
- Single credential for all payment operations

**Required:**
1. Use Vault for credential injection
2. Implement service accounts with limited permissions
3. Enable credential rotation
4. Use OAuth2 client credentials flow

---

## 2.2 Network Segmentation Analysis

### Positive: Database Isolation Implemented

```yaml
# All databases use 'expose' not 'ports'
postgresql:
  expose:
    - "5432"  # Internal only
```

**Verified:** No database ports exposed externally. ✅

### MEDIUM: Overly Permissive Network Bridges

**Finding:** Some services connect to multiple networks unnecessarily.

```yaml
# infrastructure/docker-compose.yml
nginx:
  networks:
    - dmz-network   # Expected
    - app-network   # Expected
    # Should NOT have direct data network access

prometheus:
  networks:
    - monitoring-network
    - app-network
    - data-network  # ⚠️ Has access to all databases
```

**Issue:** Prometheus can reach database ports. If Prometheus is compromised, attacker has internal network access.

**Required:** Prometheus should scrape via:
- Dedicated metrics exporters
- Metrics endpoints only (not database ports)
- Network policies in Kubernetes

### HIGH: No Internal TLS

**Finding:** All internal traffic is unencrypted.

**Evidence:**
```yaml
# Elasticsearch
hosts => ["http://elasticsearch:9200"]  # HTTP, not HTTPS

# Kafka
KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092

# Redis
# No TLS configuration present

# PostgreSQL
sslmode=prefer  # Not enforced
```

**Attack Vector:** Container escape or network compromise exposes all internal traffic including:
- Database credentials
- Customer PII
- Transaction data
- Authentication tokens

**Required for production:**
- mTLS between all services
- Service mesh (Istio/Linkerd) for automatic encryption
- Certificate rotation automation

---

## 2.3 Secrets Management Gaps

### CRITICAL: Vault Not Integrated

**Finding:** Vault is deployed but not used by any service.

**Evidence:**
```yaml
# infrastructure/docker-compose.yml
vault:
  environment:
    - VAULT_DEV_ROOT_TOKEN_ID=${VAULT_DEV_ROOT_TOKEN_ID}
    - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
```

**Issue:** Vault runs in dev mode (not production mode) and no service reads secrets from it.

**Current state:**
- All credentials in `.env` file
- Passed via Docker environment variables
- Visible in container inspection
- No rotation, no revocation, no audit

**Required:**
1. Switch Vault to production mode with file/HA storage
2. Implement Vault Agent sidecar pattern
3. Use dynamic database credentials
4. Enable secret lease/rotation

---

## 2.4 Attack Surface Analysis

### External Attack Surface (from internet)

| Port | Service | Attack Vectors |
|------|---------|----------------|
| 443 | Nginx | SSL vulnerabilities, misconfigured headers |
| 8443 | Fineract | API abuse, auth bypass, injection |
| 3000 | Grafana | Default credentials, XSS |
| 3001 | Marble | Firebase auth bypass |
| 4200 | Customer Portal | XSS, CSRF, session hijacking |
| 5601 | Kibana | No auth (if exposed) |
| 8090 | Kafka UI | No auth, data exposure |
| 8180 | Keycloak | Admin console exposure |
| 8200-8202 | Moov | API abuse, format injection |
| 8280 | Operate | Workflow data exposure |
| 8283 | Operations | Admin functionality exposure |
| 9001 | MinIO | Document/KYC data exposure |
| 9090 | Prometheus | Metrics data exposure |
| 9191 | Message Gateway | SMS injection, cost abuse |
| 26500 | Zeebe | Workflow injection (gRPC) |

**Critical Finding:** 16 ports exposed externally. Banking should have 2-3 max (web UI, API, maybe admin).

**Required:**
1. VPN/bastion for all admin interfaces
2. WAF in front of Nginx
3. API gateway with OAuth2 for all endpoints
4. Remove direct Zeebe exposure

---

# SECTION 3: BANKING EXECUTIVE FINDINGS

## 3.1 Operational Risk Assessment

### HIGH: No High Availability Configuration

**Finding:** All services run as single instances.

**Evidence:**
```yaml
# No replica configuration in any docker-compose
# No load balancer health checks
# No failover configuration
```

**Business Impact:**
- Single container failure = service outage
- Database corruption = complete data loss
- Zeebe failure = all payments stuck

**SLA Risk:**
- Cannot achieve 99.9% uptime
- No geographic redundancy
- No disaster recovery tested

**Required for production:**
- Kubernetes deployment with pod replicas
- Database clustering (Patroni for PostgreSQL)
- Zeebe clustering (3+ nodes)
- Multi-region deployment

### CRITICAL: No Backup Configuration

**Finding:** No backup jobs configured for any database.

**Evidence:** No backup scripts, no volume backup configuration, no S3 backup integration.

**Affected Data:**
| Database | Data at Risk | Impact |
|----------|--------------|--------|
| Fineract PostgreSQL | All accounts, transactions, GL | CATASTROPHIC |
| Keycloak PostgreSQL | All user identities | HIGH |
| Payment Hub MySQL | Transaction history | HIGH |
| Marble PostgreSQL | Compliance cases | MEDIUM |
| Elasticsearch | Audit logs | MEDIUM |

**Required:**
- Automated daily backups with retention
- Point-in-time recovery capability
- Cross-region backup replication
- Tested restore procedures

---

## 3.2 Vendor Dependency Analysis

### HIGH: Heavy Reliance on Unofficial Images

| Image | Maintainer | Last Update | Risk |
|-------|------------|-------------|------|
| openmf/fineract:1.11 | Mifos Community | Active | Medium |
| openmf/web-app:1.11 | Mifos Community | Active | Medium |
| openmf/ph-ee-* | Mifos Community | Active | Medium |
| moov/ach:v1.33.5 | Moov Financial | Active | Low |
| checkmarble/* | CheckMarble | Active | Medium |

**Concern:** Mifos images are community-maintained, not commercially supported.

**Business Risk:**
- Security patches depend on volunteer availability
- No SLA for vulnerability remediation
- No enterprise support contract available

**Recommendation:**
- Establish relationship with Mifos Foundation
- Consider commercial Fineract distributions
- Build internal expertise for emergency patches

### MEDIUM: Firebase Auth Dependency for Marble

**Finding:** Marble uses Firebase Authentication emulator.

**Evidence:**
```yaml
# marble/docker-compose-dev.yaml
FIREBASE_AUTH_EMULATOR_HOST: firebase-auth:9099
```

**Issue:**
- Production would require Google Firebase dependency
- User data flows through Google infrastructure
- Compliance implications for data residency

**Alternative:** Integrate Marble with Keycloak instead of Firebase.

---

## 3.3 Integration Maturity Assessment

### LOW: Manual Process Dependencies

**Finding:** Many banking operations require manual intervention.

| Process | Automation Level | Gap |
|---------|------------------|-----|
| Customer onboarding | Manual KYC review | No OCR, no automated verification |
| Sanctions screening | Semi-automated | No blocking, requires manual review |
| CTR filing | Not automated | Manual export and submission |
| Account reconciliation | Not configured | No daily balance checks |
| Interest calculation | Batch job (Fineract) | OK |
| Fee assessment | Batch job (Fineract) | OK |
| Payment processing | Workflow-based | OK |

**Required:** RPA or workflow integration for:
- Automated KYC document verification
- Automated CTR generation and submission
- Daily reconciliation reports

---

# SECTION 4: VENTURE INVESTOR FINDINGS

## 4.1 Scalability Concerns

### HIGH: Single-Node Architecture

**Finding:** No horizontal scaling configuration.

**Current Capacity (estimated per service):**
| Service | Concurrent Users | TPS | Bottleneck |
|---------|------------------|-----|------------|
| Fineract | ~100 | ~50 | Database connections (10 max) |
| Zeebe | ~1000 workflows | ~100 | Single broker |
| Elasticsearch | ~10GB logs | N/A | Single node |
| PostgreSQL | N/A | ~500 | Single instance |

**Scale Path:**
1. **Phase 1:** Kubernetes migration
2. **Phase 2:** Database read replicas
3. **Phase 3:** Zeebe clustering
4. **Phase 4:** Microservices sharding

**Investment Required:** ~$200-500K for Phase 1-2.

### MEDIUM: No Performance Baselines

**Finding:** No load testing results, no performance metrics.

**Unknown:**
- Maximum transaction throughput
- Response time under load
- Memory/CPU scaling curve
- Database query performance

**Required:** Load testing with k6 or Gatling before production.

---

## 4.2 Technical Debt Inventory

### Current Technical Debt

| Debt Item | Effort to Fix | Risk if Unfixed |
|-----------|---------------|-----------------|
| No Kubernetes deployment | 2-4 weeks | Cannot scale |
| No CI/CD pipeline | 1-2 weeks | Manual deployments, errors |
| No integration tests | 4-6 weeks | Breaking changes undetected |
| No API versioning | 2 weeks | Breaking client changes |
| Hardcoded tenant (default) | 1 week | Cannot multi-tenant |
| Firebase dependency | 2 weeks | Google lock-in |
| Self-signed certificates | 1 day | Cannot go live |
| No monitoring alerts | 1 week | Outages undetected |

**Total Remediation:** ~3-4 months of engineering effort.

---

## 4.3 Regulatory Exposure Assessment

### License Risk Analysis

| Component | License | Commercial Use | Risk |
|-----------|---------|----------------|------|
| Apache Fineract | Apache 2.0 | ✅ Allowed | None |
| Mifos X | MPL 2.0 | ✅ Allowed | Low (modifications must be open) |
| Marble | AGPL 3.0? | ⚠️ Check | HIGH if AGPL |
| Moov | Apache 2.0 | ✅ Allowed | None |
| Keycloak | Apache 2.0 | ✅ Allowed | None |
| Elasticsearch | Elastic License | ⚠️ Limited | Medium (check usage) |

**Action Required:** Legal review of Marble and Elasticsearch licenses.

### Regulatory Burden Estimate

**To operate as:**

**Money Transmitter (State level):**
- 50+ state licenses required
- ~$5M in surety bonds
- Annual examinations
- Ongoing compliance cost: ~$500K/year

**Bank (Federal/State charter):**
- OCC or state charter application
- ~$20M minimum capital
- FDIC insurance
- BSA/AML program
- CRA compliance
- Ongoing compliance cost: ~$2M/year

**Partnership with Sponsor Bank:**
- BIN sponsorship agreement
- Shared compliance burden
- Revenue share model
- Lower capital requirements

---

# SECTION 5: CRITICAL INTEGRATION ISSUES SUMMARY

## Must-Fix Before Production

| # | Issue | Severity | Owner | Effort |
|---|-------|----------|-------|--------|
| 1 | Marble not integrated in payment flow | CRITICAL | Integration | 1 week |
| 2 | Zeebe authentication disabled | CRITICAL | Security | 3 days |
| 3 | No database backups | CRITICAL | Infrastructure | 1 week |
| 4 | No high availability | HIGH | Infrastructure | 4 weeks |
| 5 | Internal traffic unencrypted | HIGH | Security | 2 weeks |
| 6 | No distributed tracing | HIGH | Observability | 1 week |
| 7 | Vault not integrated | HIGH | Security | 2 weeks |
| 8 | 16 ports exposed | HIGH | Security | 1 week |
| 9 | CTR filing not automated | HIGH | Compliance | 2 weeks |
| 10 | No load testing | MEDIUM | QA | 2 weeks |

---

# SECTION 6: POSITIVE INTEGRATION FINDINGS

## What Was Done Well

| Area | Implementation | Rating |
|------|----------------|--------|
| Network segmentation | 6 isolated networks | ✅ Excellent |
| Database port isolation | All internal only | ✅ Excellent |
| Environment-based config | .env file pattern | ✅ Good |
| SSL on API endpoint | Fineract HTTPS | ✅ Good |
| Rate limiting | Nginx zones | ✅ Good |
| Security headers | CSP, HSTS, XSS | ✅ Good |
| PII masking in logs | Logstash filters | ✅ Good |
| Container resource limits | CPU/memory caps | ✅ Good |
| Health checks | All key services | ✅ Good |
| Image version pinning | No :latest tags | ✅ Good |

---

# SECTION 7: RECOMMENDED ARCHITECTURE CHANGES

## Proposed Integration Architecture

```
                        ┌─────────────────┐
                        │  WAF / DDoS     │
                        │  (Cloudflare)   │
                        └────────┬────────┘
                                 │
                        ┌────────▼────────┐
                        │  API Gateway    │
                        │  (Kong/AWS)     │
                        │  OAuth2, Quotas │
                        └────────┬────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
┌────────▼────────┐    ┌────────▼────────┐    ┌────────▼────────┐
│  Customer Web   │    │  Mobile App     │    │  Staff Portal   │
│  (Cloudfront)   │    │  (Native)       │    │  (VPN Required) │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                        ┌────────▼────────┐
                        │  Keycloak       │
                        │  (OAuth2/OIDC)  │
                        └────────┬────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
┌────────▼────────┐    ┌────────▼────────┐    ┌────────▼────────┐
│  Fineract       │◄───│  Payment Hub    │───►│  Marble         │
│  (Core Banking) │    │  (Zeebe mTLS)   │    │  (Compliance)   │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  PostgreSQL     │    │  Moov           │    │  FinCEN         │
│  (RDS/Aurora)   │    │  (ACH/Wire)     │    │  (E-File API)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

# SECTION 8: CERTIFICATION READINESS

| Certification | Current State | Gap | Effort |
|---------------|---------------|-----|--------|
| SOC 2 Type II | Not started | Full program | 6-12 months |
| PCI-DSS | Partial | Key management, logging | 3-6 months |
| SOX | Not applicable | N/A | N/A |
| ISO 27001 | Not started | Full ISMS | 6-12 months |
| FFIEC | Not audited | BSA, IT examination | 3-6 months |

---

**Report Prepared By:**
Multi-Stakeholder Audit Team
January 2026

**Distribution:**
- Board of Directors
- Chief Technology Officer
- Chief Compliance Officer
- Chief Information Security Officer
- Legal Counsel
