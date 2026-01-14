# Fineract & Mifos Bank-in-a-Box

A complete, institutional-grade open-source banking infrastructure stack for building and running a digital bank in the United States. This setup includes everything needed for core banking, compliance, payments, and enterprise infrastructure.

## Complete Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                        INSTITUTIONAL BANKING STACK                                │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                           USER INTERFACES                                    │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │ │
│  │  │  Staff UI   │  │ Customer UI │  │ Mobile App  │  │  Operations UI      │ │ │
│  │  │  (Mifos X)  │  │  (Portal)   │  │  (Android)  │  │  (Payment Hub)      │ │ │
│  │  │  Port: 80   │  │  Port: 4200 │  │  Fineract   │  │  Port: 8283         │ │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                         API GATEWAY (NGINX)                                  │ │
│  │              SSL Termination • Rate Limiting • Load Balancing               │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                           CORE BANKING                                       │ │
│  │  ┌──────────────────────────────────────────────────────────────────────┐   │ │
│  │  │                     APACHE FINERACT                                   │   │ │
│  │  │    Accounts • Loans • Deposits • Ledger • Multi-tenancy • APIs       │   │ │
│  │  │                        Port: 8080                                     │   │ │
│  │  └──────────────────────────────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                      PAYMENT ORCHESTRATION                                   │ │
│  │  ┌───────────────┐  ┌────────────────────┐  ┌────────────────────────────┐  │ │
│  │  │  Payment Hub  │  │   Zeebe/Camunda    │  │      Message Gateway       │  │ │
│  │  │   (Ph-EE)     │◄─┤   (Workflows)      │  │    (SMS/Email via Twilio)  │  │ │
│  │  │  Port: 26500  │  │   Port: 26500      │  │       Port: 9191           │  │ │
│  │  └───────────────┘  └────────────────────┘  └────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                          │
│  ┌──────────────────────────────────────┬──────────────────────────────────────┐ │
│  │          COMPLIANCE                  │           PAYMENT RAILS              │ │
│  │  ┌────────────────────────────────┐  │  ┌────────────────────────────────┐  │ │
│  │  │           MARBLE               │  │  │            MOOV                │  │ │
│  │  │  • Sanctions Screening (OFAC)  │  │  │  • ACH Processing (8200)       │  │ │
│  │  │  • Transaction Monitoring      │  │  │  • Wire/FedWire (8201)         │  │ │
│  │  │  • Fraud Detection             │  │  │  • ISO 20022 (8202)            │  │ │
│  │  │  • Case Management             │  │  │  • NACHA Format                │  │ │
│  │  │  UI: 3001 / API: 8180          │  │  │                                │  │ │
│  │  └────────────────────────────────┘  │  └────────────────────────────────┘  │ │
│  └──────────────────────────────────────┴──────────────────────────────────────┘ │
│                                       │                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                       ENTERPRISE INFRASTRUCTURE                              │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │ │
│  │  │  Keycloak   │ │   MinIO     │ │   Kafka     │ │    Vault    │            │ │
│  │  │   (Auth)    │ │  (Docs/S3)  │ │  (Events)   │ │  (Secrets)  │            │ │
│  │  │   + MFA     │ │   + KYC     │ │   + Audit   │ │   + Keys    │            │ │
│  │  │  Port: 8180 │ │  Port: 9001 │ │  Port: 9092 │ │  Port: 8200 │            │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘            │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │ │
│  │  │    ELK      │ │  Prometheus │ │   Grafana   │ │    Redis    │            │ │
│  │  │   Stack     │ │  (Metrics)  │ │ (Dashboard) │ │  (Cache)    │            │ │
│  │  │  (Logging)  │ │             │ │             │ │             │            │ │
│  │  │  Port: 5601 │ │  Port: 9090 │ │  Port: 3000 │ │  Port: 6379 │            │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘            │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                            DATABASES                                         │ │
│  │  PostgreSQL (Fineract) • PostgreSQL (Keycloak) • MySQL (Gateway)            │ │
│  │  Elasticsearch (Logs/Search) • Redis (Cache/Sessions)                       │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Components

### Core Banking
| Component | Purpose | Port | Source |
|-----------|---------|------|--------|
| **Apache Fineract** | Core banking ledger, accounts, loans | 8080 | Apache Foundation |
| **Mifos X** | Staff banking dashboard | 80 | Mifos Initiative |
| **Customer Portal** | Customer self-service | 4200 | Mifos Initiative |

### Compliance & Risk
| Component | Purpose | Port | Source |
|-----------|---------|------|--------|
| **Marble** | Sanctions screening, fraud detection | 3001, 8180 | CheckMarble |
| **Yente** | OpenSanctions integration | 8001 | OpenSanctions |

### Payment Rails
| Component | Purpose | Port | Source |
|-----------|---------|------|--------|
| **Moov ACH** | US domestic ACH processing | 8200 | Moov Financial |
| **Moov Wire** | FedWire transfers | 8201 | Moov Financial |
| **Moov ISO20022** | International messaging | 8202 | Moov Financial |
| **Payment Hub EE** | Payment orchestration | 26500 | Mifos Initiative |

### Enterprise Infrastructure
| Component | Purpose | Port | Source |
|-----------|---------|------|--------|
| **Keycloak** | Identity, OAuth2, MFA, SSO | 8180 | Red Hat |
| **MinIO** | S3-compatible document storage | 9000, 9001 | MinIO |
| **Kafka** | Event streaming | 9092 | Apache/Confluent |
| **Elasticsearch** | Search & audit logging | 9200 | Elastic |
| **Kibana** | Log visualization | 5601 | Elastic |
| **Vault** | Secrets management | 8200 | HashiCorp |
| **Redis** | Caching & sessions | 6379 | Redis |
| **Prometheus** | Metrics collection | 9090 | Prometheus |
| **Grafana** | Monitoring dashboards | 3000 | Grafana Labs |
| **Message Gateway** | SMS/Email notifications | 9191 | Mifos Initiative |

## Quick Start

### Prerequisites
- Docker Desktop (8GB+ RAM allocated)
- Git

### Start Everything

```bash
# Clone the repository
git clone https://github.com/reeceway/fineract-mifos-setup.git
cd fineract-mifos-setup

# Start all services
./start-all.sh
```

### Stop Everything

```bash
./stop-all.sh
```

## Access URLs

### User Interfaces
| Interface | URL | Credentials |
|-----------|-----|-------------|
| Staff Portal | http://localhost | mifos / password |
| Customer Portal | http://localhost:4200 | (create via staff portal) |
| Marble Compliance | http://localhost:3001 | jbe@zorg.com |

### Administration
| Interface | URL | Credentials |
|-----------|-----|-------------|
| Keycloak Admin | http://localhost:8180 | admin / admin |
| MinIO Console | http://localhost:9001 | minio_admin / minio_password |
| Kibana (Logs) | http://localhost:5601 | - |
| Grafana | http://localhost:3000 | admin / admin |
| Kafka UI | http://localhost:8090 | - |

### APIs
| Service | URL |
|---------|-----|
| Fineract API | http://localhost:8080/fineract-provider/api/v1 |
| Marble API | http://localhost:8180 |
| Moov ACH | http://localhost:8200 |
| Moov Wire | http://localhost:8201 |

## Directory Structure

```
fineract-mifos-setup/
├── README.md                    # This file
├── USER_GUIDE.md               # Complete banking operations guide
├── AI_GUIDE.md                 # Guide for AI assistants
├── start-all.sh                # Start all services
├── stop-all.sh                 # Stop all services
│
├── mifosplatform-25.03.22.RELEASE/
│   └── docker/mifosx-postgresql/   # Core Fineract + Mifos
│
├── customer-portal/                # Customer self-service UI
│   └── docker-compose.yml
│
├── marble/                         # Compliance & risk engine
│   ├── docker-compose-dev.yaml
│   └── .env.dev
│
├── moov/                           # Payment rails (ACH, Wire)
│   └── docker-compose.yml
│
├── payment-hub-ee/                 # Payment orchestration
│   └── docker-compose.yml
│
├── infrastructure/                 # Enterprise infrastructure
│   ├── docker-compose.yml         # All infrastructure services
│   ├── nginx/                     # API Gateway config
│   ├── logstash/                  # Log processing
│   └── prometheus/                # Metrics config
│
└── self-service-app/              # Mobile app source (optional)
```

## US Banking Compliance Features

### BSA/AML Compliance
- **CTR Filing**: Automatic flagging for cash transactions >$10,000
- **SAR Support**: Suspicious activity case management via Marble
- **OFAC Screening**: Real-time sanctions checks via Yente/OpenSanctions

### Security
- **Authentication**: OAuth2/OIDC via Keycloak with MFA support
- **Encryption**: TLS 1.2/1.3 via NGINX, encryption at rest
- **Audit Logging**: Complete audit trail via ELK Stack
- **Secrets Management**: Secure credential storage via Vault

### Payment Processing
- **ACH**: NACHA-compliant file generation via Moov
- **Wire**: FedWire message handling via Moov
- **ISO 20022**: International payment messaging

## Production Deployment

For production deployment, you'll need:

1. **Regulatory**: Bank charter or money transmitter licenses
2. **Infrastructure**: Kubernetes cluster, managed databases
3. **Security**: Real SSL certificates, WAF, penetration testing
4. **Compliance**: SOC 2 Type II, PCI-DSS (if card processing)

See [USER_GUIDE.md](USER_GUIDE.md) for detailed production guidance.

## Documentation

- [USER_GUIDE.md](USER_GUIDE.md) - Complete banking operations guide
- [AI_GUIDE.md](AI_GUIDE.md) - Context for AI assistants
- [Fineract Docs](https://fineract.apache.org/docs/)
- [Mifos Docs](https://docs.mifos.org/)

## Technology Stack

| Layer | Technologies |
|-------|-------------|
| **Core Banking** | Java 17, Spring Boot, Apache Fineract |
| **Databases** | PostgreSQL, MySQL, Redis, Elasticsearch |
| **Messaging** | Apache Kafka |
| **Frontend** | Angular, React |
| **Mobile** | Kotlin Multiplatform |
| **Auth** | Keycloak, OAuth2, OIDC |
| **Containers** | Docker, Kubernetes |
| **Monitoring** | Prometheus, Grafana, ELK |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

- Apache Fineract: Apache License 2.0
- Mifos X: Mozilla Public License 2.0
- Other components: See individual licenses

## Support

- GitHub Issues: https://github.com/reeceway/fineract-mifos-setup/issues
- Mifos Community: https://mifos.org/community/
- Apache Fineract: dev@fineract.apache.org