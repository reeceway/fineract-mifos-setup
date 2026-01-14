# Fineract & Mifos Bank-in-a-Box

A complete open-source banking infrastructure stack for building and running a digital bank. This setup includes core banking, compliance, and payment rails - everything you need to operate a bank.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Your Banking Stack                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐ │
│  │   Mifos X   │    │  Fineract   │    │     Payment Hub EE      │ │
│  │   Web UI    │───▶│  Core API   │───▶│   (Zeebe Orchestrator)  │ │
│  │  Port: 80   │    │ Port: 8080  │    │     Port: 26500         │ │
│  └─────────────┘    └─────────────┘    └───────────┬─────────────┘ │
│                                                     │               │
│                     ┌───────────────────────────────┼───────────┐   │
│                     │                               │           │   │
│                     ▼                               ▼           │   │
│  ┌─────────────────────────────┐    ┌─────────────────────────┐ │   │
│  │         Marble              │    │          Moov           │ │   │
│  │   Compliance & Risk Engine  │    │    Payment Rails        │ │   │
│  │   - Sanctions Screening     │    │    - ACH (Port 8200)    │ │   │
│  │   - Transaction Monitoring  │    │    - Wire (Port 8201)   │ │   │
│  │   - Fraud Detection         │    │    - ISO20022 (8202)    │ │   │
│  │   UI: 3001 / API: 8180      │    └─────────────────────────┘ │   │
│  └─────────────────────────────┘                                │   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose | Port(s) |
|-----------|---------|---------|
| **Apache Fineract** | Core banking ledger, accounts, loans, deposits | 8080 |
| **Mifos X** | Web-based banking dashboard UI | 80 |
| **Marble** | Compliance engine - sanctions, fraud, risk | 3001 (UI), 8180 (API) |
| **Moov ACH** | US domestic ACH payment processing | 8200 |
| **Moov Wire** | FedWire transfers | 8201 |
| **Moov ISO20022** | International payment messaging | 8202 |
| **Payment Hub EE** | Payment orchestration (Zeebe/Camunda) | 26500 |

## Quick Start

### Prerequisites

- Docker Desktop installed and running
- Git
- 8GB+ RAM recommended

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/fineract-mifos-setup.git
cd fineract-mifos-setup
```

### 2. Start All Services

```bash
# Start Fineract & Mifos (Core Banking)
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
docker-compose up -d
cd ../../..

# Start Marble (Compliance)
cd marble
docker-compose -f docker-compose-dev.yaml --env-file .env.dev up -d
cd ..

# Start Moov (Payment Rails)
cd moov
docker-compose up -d
cd ..

# Start Payment Hub (Orchestration)
cd payment-hub-ee
docker-compose up -d
cd ..
```

### 3. Access the Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Mifos Web UI | http://localhost | mifos / password |
| Fineract API | http://localhost:8080/fineract-provider/api/v1 | mifos / password |
| Marble UI | http://localhost:3001 | jbe@zorg.com |
| Firebase Auth (Marble) | http://localhost:4000 | - |

## Directory Structure

```
fineract-mifos-setup/
├── README.md                 # This file
├── USER_GUIDE.md            # Complete banking operations guide
├── AI_GUIDE.md              # Guide for AI assistants
├── apache-fineract-src-1.14.0/   # Fineract source code
├── mifosplatform-25.03.22.RELEASE/
│   ├── docker/
│   │   └── mifosx-postgresql/    # Docker setup for Fineract + Mifos
│   └── webapp/                   # Mifos X web application
├── marble/                       # Compliance & risk engine
├── moov/                         # Payment rails (ACH, Wire, ISO20022)
└── payment-hub-ee/               # Payment orchestration hub
```

## Features

### Core Banking (Fineract)
- Client/Customer management
- Savings accounts with interest calculation
- Loan origination and management
- Fixed and recurring deposits
- Share accounts
- Multi-currency support
- Chart of accounts & general ledger
- Multi-tenant architecture

### Compliance (Marble)
- OFAC sanctions screening
- Transaction monitoring rules
- Fraud detection
- Case management
- Audit trails

### Payment Processing (Moov)
- ACH file creation and validation
- FedWire message handling
- ISO 20022 message formatting
- NACHA format support

## API Examples

### Create a Client

```bash
curl -X POST \
  -u mifos:password \
  -H "Fineract-Platform-TenantId: default" \
  -H "Content-Type: application/json" \
  -d '{
    "officeId": 1,
    "firstname": "John",
    "lastname": "Doe",
    "active": true,
    "activationDate": "01 January 2024",
    "dateFormat": "dd MMMM yyyy",
    "locale": "en"
  }' \
  http://localhost:8080/fineract-provider/api/v1/clients
```

### Check Account Balance

```bash
curl -u mifos:password \
  -H "Fineract-Platform-TenantId: default" \
  http://localhost:8080/fineract-provider/api/v1/savingsaccounts/{accountId}
```

### Create ACH File

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "immediateOrigin": "123456789",
    "immediateDestination": "987654321",
    "originName": "Your Bank",
    "destinationName": "Receiving Bank"
  }' \
  http://localhost:8200/files/create
```

## Configuration

### Environment Variables

Key configuration files:
- `mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql/docker-compose.yml`
- `marble/.env.dev`
- `moov/docker-compose.yml`
- `payment-hub-ee/docker-compose.yml`

### Ports Summary

| Port | Service |
|------|---------|
| 80 | Mifos Web UI |
| 3001 | Marble UI |
| 4000 | Firebase Auth Emulator |
| 5432 | PostgreSQL (Fineract) |
| 5433 | PostgreSQL (Marble) |
| 8080 | Fineract API |
| 8180 | Marble API |
| 8200 | Moov ACH |
| 8201 | Moov Wire |
| 8202 | Moov ISO20022 |
| 9099 | Firebase Auth |
| 9200-9202 | Elasticsearch |
| 26500 | Zeebe Gateway |

## Documentation

- [USER_GUIDE.md](USER_GUIDE.md) - Complete guide for banking operations
- [AI_GUIDE.md](AI_GUIDE.md) - Context for AI assistants working with this codebase
- [Fineract Docs](https://fineract.apache.org/docs/)
- [Mifos Community](https://mifos.org/)
- [Marble Docs](https://docs.checkmarble.com/)
- [Moov Docs](https://moov.io/docs/)

## Stopping Services

```bash
# Stop all services
cd payment-hub-ee && docker-compose down
cd ../moov && docker-compose down
cd ../marble && docker-compose down
cd ../mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql && docker-compose down

# Or stop everything at once
docker stop $(docker ps -q)
```

## Production Considerations

Before deploying to production:

1. **Security**: Enable HTTPS, change all default passwords
2. **Database**: Use managed PostgreSQL (AWS RDS, Cloud SQL)
3. **Scaling**: Deploy on Kubernetes with multiple replicas
4. **Compliance**: Integrate with real OFAC lists, configure CTR/SAR filing
5. **Monitoring**: Set up logging, metrics, and alerting

See [USER_GUIDE.md](USER_GUIDE.md) for detailed production deployment instructions.

## License

- Apache Fineract: Apache License 2.0
- Mifos X: Mozilla Public License 2.0
- Marble: Check their license
- Moov: Apache License 2.0

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Support

- GitHub Issues: For bugs and feature requests
- Mifos Community: https://mifos.org/community/
- Apache Fineract Mailing List: dev@fineract.apache.org