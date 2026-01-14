# AI Assistant Guide for Fineract & Mifos Banking Stack

This guide provides context for AI assistants (Claude, GPT, Copilot, etc.) working with this banking infrastructure codebase.

## Project Overview

This is a **complete open-source banking stack** that combines:
- **Apache Fineract** - Core banking system (ledger, accounts, loans)
- **Mifos X** - Web UI for banking operations
- **Marble** - Compliance and risk engine
- **Moov** - US payment rails (ACH, Wire)
- **Payment Hub EE** - Payment orchestration

## Architecture Context

```
User Request → Mifos UI → Fineract API → Payment Hub → Marble (compliance check)
                                                    → Moov (payment execution)
```

### Component Relationships

1. **Mifos X** is the frontend that calls Fineract's REST API
2. **Fineract** is the core banking engine - all business logic lives here
3. **Payment Hub** orchestrates multi-step payment workflows using Zeebe/Camunda
4. **Marble** screens transactions for sanctions/fraud before execution
5. **Moov** generates ACH/Wire files for actual fund movement

## Key Technical Details

### Fineract API

- **Base URL**: `http://localhost:8080/fineract-provider/api/v1`
- **Auth**: Basic auth with `mifos:password`
- **Tenant Header**: `Fineract-Platform-TenantId: default`
- **Content-Type**: `application/json`

#### Important Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/clients` | Customer management |
| `/savingsaccounts` | Savings accounts |
| `/loans` | Loan accounts |
| `/offices` | Branch/office hierarchy |
| `/staff` | Employee management |
| `/glaccounts` | Chart of accounts |
| `/journalentries` | Accounting entries |
| `/datatables` | Custom fields |

#### Example API Call Pattern

```bash
curl -X POST \
  -u mifos:password \
  -H "Fineract-Platform-TenantId: default" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}' \
  http://localhost:8080/fineract-provider/api/v1/{endpoint}
```

### Marble API

- **Base URL**: `http://localhost:8180`
- **UI**: `http://localhost:3001`
- **Auth**: Firebase authentication (emulator at port 9099)

### Moov APIs

| Service | URL | Purpose |
|---------|-----|---------|
| ACH | `http://localhost:8200` | NACHA file handling |
| Wire | `http://localhost:8201` | FedWire messages |
| ISO20022 | `http://localhost:8202` | International messages |

## Common Tasks & How to Help

### 1. Creating Banking Products

When user asks to create a savings or loan product:
- Navigate them through Fineract's product configuration
- Key parameters: interest rates, terms, fees, accounting mappings
- Products must be created before accounts can be opened

### 2. Customer Onboarding

Workflow:
1. Create client in Fineract (`POST /clients`)
2. Upload KYC documents
3. Activate client
4. Open accounts (savings, loans)

### 3. Processing Payments

For internal transfers:
- Use Fineract's account transfer API

For external ACH:
1. Create ACH file via Moov (`POST http://localhost:8200/files/create`)
2. Add batches and entries
3. Validate file
4. Submit to Fed (production only)

### 4. Compliance Checks

Marble integration points:
- New customer screening against OFAC
- Transaction monitoring rules
- Case management for alerts

## File Structure Reference

```
fineract-mifos-setup/
├── apache-fineract-src-1.14.0/     # Fineract source (Java/Gradle)
│   ├── fineract-provider/          # Main API module
│   ├── fineract-client/            # Java client SDK
│   └── docker-compose*.yml         # Various Docker configs
│
├── mifosplatform-25.03.22.RELEASE/
│   ├── docker/mifosx-postgresql/   # Production Docker setup
│   │   └── docker-compose.yml      # Main compose file
│   └── webapp/                     # Angular web application
│
├── marble/                         # Compliance engine
│   ├── docker-compose-dev.yaml     # Dev Docker setup
│   ├── .env.dev                    # Environment config
│   └── contrib/                    # Configuration files
│
├── moov/                           # Payment rails
│   └── docker-compose.yml          # ACH, Wire, ISO20022 services
│
└── payment-hub-ee/                 # Payment orchestration
    ├── docker-compose.yml          # Zeebe, Elasticsearch, MySQL
    ├── orchestration/bpmn/         # Workflow definitions
    └── helm/                       # Kubernetes charts
```

## Database Schema Context

### Fineract Core Tables

| Table | Purpose |
|-------|---------|
| `m_client` | Customer records |
| `m_savings_account` | Savings accounts |
| `m_loan` | Loan accounts |
| `m_office` | Branch hierarchy |
| `m_staff` | Employees |
| `acc_gl_account` | Chart of accounts |
| `acc_gl_journal_entry` | Ledger entries |
| `m_product_loan` | Loan products |
| `m_savings_product` | Savings products |

### Multi-Tenancy

Fineract supports multiple tenants:
- `fineract_tenants` database stores tenant configs
- Each tenant has its own `fineract_default` database
- Tenant specified via `Fineract-Platform-TenantId` header

## Common Issues & Solutions

### Issue: Port Conflicts

If services fail to start due to port conflicts:
```bash
# Check what's using a port
lsof -i :8080

# Stop conflicting containers
docker stop $(docker ps -q)
```

### Issue: Database Connection Failures

Fineract needs PostgreSQL healthy before starting:
```bash
# Check PostgreSQL status
docker logs mifosx-postgresql-postgresql-1

# Restart if needed
docker-compose restart postgresql
```

### Issue: Marble Auth Problems

Marble uses Firebase emulator for dev:
```bash
# Check Firebase emulator
docker logs firebase-auth

# Access emulator UI
open http://localhost:4000
```

### Issue: Platform Mismatch (M1/M2 Mac)

Some images are amd64 only. Docker Desktop handles emulation but it's slower:
```yaml
# Add to service if needed
platform: linux/amd64
```

## Integration Patterns

### Fineract Event Listeners

Fineract emits events that can trigger external actions:
- Post-transaction hooks
- Account activation events
- Loan disbursement events

### Payment Hub Workflows

BPMN workflows in `payment-hub-ee/orchestration/bpmn/`:
- Define multi-step payment processes
- Integrate compliance checks
- Handle payment routing

### Marble Decision API

```bash
# Example: Screen a customer
curl -X POST http://localhost:8180/api/decisions \
  -H "Content-Type: application/json" \
  -d '{
    "scenario_id": "customer_onboarding",
    "data": {
      "customer_name": "John Doe",
      "country": "US"
    }
  }'
```

## Development Tips

### Running Locally

1. Ensure Docker has 8GB+ RAM allocated
2. Start services in order: DB → Fineract → Marble → Moov → Payment Hub
3. Wait for health checks before testing

### Testing API Changes

```bash
# Quick health check
curl http://localhost:8080/fineract-provider/api/v1/offices \
  -u mifos:password \
  -H "Fineract-Platform-TenantId: default"
```

### Viewing Logs

```bash
# Fineract logs
docker logs -f mifosx-postgresql-fineract-server-1

# All logs
docker-compose logs -f
```

## Regulatory Context

When helping with compliance features, be aware of:

- **BSA/AML**: Bank Secrecy Act requires CTR for cash >$10k
- **OFAC**: Must screen against sanctions lists
- **KYC/CIP**: Customer identification requirements
- **SAR**: Suspicious activity reporting obligations

## API Response Patterns

### Success Response
```json
{
  "resourceId": 123,
  "changes": {...}
}
```

### Error Response
```json
{
  "developerMessage": "...",
  "httpStatusCode": "400",
  "defaultUserMessage": "...",
  "errors": [...]
}
```

## Helping Users Effectively

1. **For UI questions**: Guide them through Mifos X interface
2. **For API questions**: Provide curl examples with all required headers
3. **For compliance questions**: Explain Marble rule configuration
4. **For payments questions**: Explain ACH/Wire file formats via Moov
5. **For production questions**: Reference USER_GUIDE.md production section

## Quick Reference Commands

```bash
# Start everything
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql && docker-compose up -d
cd ../../.. && cd marble && docker-compose -f docker-compose-dev.yaml --env-file .env.dev up -d
cd ../moov && docker-compose up -d
cd ../payment-hub-ee && docker-compose up -d

# Stop everything
docker stop $(docker ps -q)

# Clean restart
docker-compose down -v && docker-compose up -d

# Check all services
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Links to Official Documentation

- Fineract: https://fineract.apache.org/docs/
- Mifos X: https://mifos.gitbook.io/docs/
- Marble: https://docs.checkmarble.com/
- Moov: https://moov.io/docs/
- Zeebe: https://docs.camunda.io/docs/components/zeebe/