# Fineract & Mifos Bank Operations Guide

## Table of Contents
1. [Getting Started](#getting-started)
2. [Initial Bank Setup](#initial-bank-setup)
3. [Office & Branch Management](#office--branch-management)
4. [Staff Management](#staff-management)
5. [Product Configuration](#product-configuration)
6. [Customer Onboarding](#customer-onboarding)
7. [Account Operations](#account-operations)
8. [Loan Management](#loan-management)
9. [Payment Processing](#payment-processing)
10. [Compliance & Risk (Marble)](#compliance--risk-marble)
11. [ACH & Wire Transfers (Moov)](#ach--wire-transfers-moov)
12. [Reports & Analytics](#reports--analytics)
13. [Going to Production](#going-to-production)

---

## Getting Started

### Access URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Mifos Web UI | http://localhost | Main banking dashboard |
| Fineract API | http://localhost:8080/fineract-provider/api/v1 | Backend API |
| Marble (Compliance) | http://localhost:3001 | Risk & sanctions screening |
| Moov ACH | http://localhost:8200 | ACH file processing |

### Default Login Credentials

```
Username: mifos
Password: password
Tenant ID: default
```

### First Login

1. Open http://localhost in your browser
2. Enter username: `mifos`
3. Enter password: `password`
4. Click "Sign In"

---

## Initial Bank Setup

### Step 1: Configure Organization Settings

1. Navigate to **Admin → Organization**
2. Set your organization details:
   - Organization Name
   - Currency (USD, EUR, etc.)
   - Date Format
   - Locale

### Step 2: Set Up Chart of Accounts

The Chart of Accounts defines how money flows through your bank.

1. Go to **Accounting → Chart of Accounts**
2. The default accounts are:
   - **Assets** (1xxxx): Cash, Loans, Fixed Assets
   - **Liabilities** (2xxxx): Deposits, Borrowings
   - **Equity** (3xxxx): Capital, Retained Earnings
   - **Income** (4xxxx): Interest Income, Fees
   - **Expenses** (5xxxx): Operating Costs

#### Creating a New GL Account

1. Click **+ Create GL Account**
2. Fill in:
   - Account Name: e.g., "Customer Savings"
   - GL Code: e.g., "20001"
   - Account Type: Liability (for deposits)
   - Usage: Detail
   - Parent Account: Select appropriate parent
3. Click **Submit**

### Step 3: Define Payment Types

1. Go to **Admin → Payment Types**
2. Add payment methods your bank accepts:
   - Cash
   - Check
   - Bank Transfer
   - ACH
   - Wire Transfer
   - Mobile Money

---

## Office & Branch Management

### Creating the Head Office

Your head office is created by default. To modify:

1. Go to **Admin → Offices**
2. Click on "Head Office"
3. Update details as needed

### Adding Branch Offices

1. Go to **Admin → Offices**
2. Click **+ Create Office**
3. Fill in:
   ```
   Office Name: Downtown Branch
   Parent Office: Head Office
   Opening Date: [Select Date]
   External ID: BR001 (optional, for integration)
   ```
4. Click **Submit**

### Office Hierarchy Example

```
Head Office (HQ)
├── Regional Office - East
│   ├── Downtown Branch
│   ├── Uptown Branch
│   └── Airport Branch
├── Regional Office - West
│   ├── Westside Branch
│   └── Beach Branch
└── Online Banking Division
```

---

## Staff Management

### Adding Staff Members

1. Go to **Admin → Staff**
2. Click **+ Create Staff**
3. Fill in:
   ```
   First Name: John
   Last Name: Smith
   Office: Downtown Branch
   Is Loan Officer: Yes/No
   Is Active: Yes
   Mobile Number: +1-555-0123
   ```
4. Click **Submit**

### Creating User Accounts for Staff

1. Go to **Admin → Users**
2. Click **+ Create User**
3. Fill in:
   ```
   Username: john.smith
   First Name: John
   Last Name: Smith
   Email: john.smith@yourbank.com
   Office: Downtown Branch
   Staff: John Smith
   Roles: [Select appropriate roles]
   ```
4. Click **Submit**

### User Roles

| Role | Permissions |
|------|-------------|
| Super User | Full system access |
| Admin | Administrative functions |
| Branch Manager | Branch-level operations |
| Loan Officer | Loan management |
| Teller | Cash transactions |
| Read Only | View-only access |

#### Creating Custom Roles

1. Go to **Admin → Roles**
2. Click **+ Create Role**
3. Name the role and select permissions
4. Click **Submit**

---

## Product Configuration

### Savings Products

Savings products define the terms for customer deposit accounts.

1. Go to **Products → Savings Products**
2. Click **+ Create Savings Product**
3. **Details Tab**:
   ```
   Product Name: Basic Savings Account
   Short Name: BSA
   Description: Standard savings account for individuals
   Currency: USD
   Decimal Places: 2
   ```

4. **Terms Tab**:
   ```
   Nominal Annual Interest: 2.5%
   Interest Compounding Period: Monthly
   Interest Posting Period: Quarterly
   Interest Calculation: Daily Balance
   Days in Year: 365
   ```

5. **Settings Tab**:
   ```
   Minimum Opening Balance: $25.00
   Lock-in Period: None
   Withdrawal Fee: $0
   Allow Overdraft: No
   ```

6. **Accounting Tab**:
   ```
   Savings Control: 20001 (Liability)
   Savings Reference: 10001 (Asset - Cash)
   Interest Payable: 20010 (Liability)
   Interest Expense: 50001 (Expense)
   ```

7. Click **Submit**

### Loan Products

1. Go to **Products → Loan Products**
2. Click **+ Create Loan Product**
3. **Details Tab**:
   ```
   Product Name: Personal Loan
   Short Name: PL
   Fund: None
   Currency: USD
   ```

4. **Terms Tab**:
   ```
   Principal: Min $1,000 / Default $5,000 / Max $50,000
   Number of Repayments: Min 6 / Default 12 / Max 60
   Nominal Interest Rate: 8.99% per year
   Repayment Frequency: Monthly
   Interest Method: Declining Balance
   Amortization: Equal Installments
   ```

5. **Settings Tab**:
   ```
   Grace Period: 0 days
   Arrears Tolerance: 3 days
   Allow Prepayments: Yes
   ```

6. **Accounting Tab**:
   ```
   Loan Portfolio: 10100 (Asset)
   Interest Receivable: 10101 (Asset)
   Interest Income: 40001 (Income)
   Losses Written Off: 50100 (Expense)
   ```

7. Click **Submit**

---

## Customer Onboarding

### Creating a New Customer (Client)

1. Go to **Clients** in the left menu
2. Click **+ Create Client**
3. **Personal Information**:
   ```
   Office: Downtown Branch
   Staff: John Smith (assigned officer)
   First Name: Jane
   Middle Name: Marie
   Last Name: Doe
   Date of Birth: 01/15/1985
   Gender: Female
   Mobile: +1-555-0199
   ```

4. **Address**:
   ```
   Address Line 1: 123 Main Street
   City: New York
   State: NY
   Postal Code: 10001
   Country: USA
   ```

5. **Identification**:
   ```
   ID Type: Driver's License
   ID Number: D12345678
   ```

6. Click **Submit**

### Customer Verification (KYC)

After creating a customer, complete KYC:

1. Open the client's profile
2. Go to **Documents** tab
3. Upload required documents:
   - Government ID (front/back)
   - Proof of Address (utility bill)
   - Signature Card

4. Go to **Identifiers** tab
5. Add identification numbers:
   - SSN (last 4 digits)
   - Tax ID

### Activating a Customer

New customers are in "Pending" status. To activate:

1. Open client profile
2. Click **Activate** button
3. Confirm activation date
4. Client is now active and can open accounts

---

## Account Operations

### Opening a Savings Account

1. Open the client's profile
2. Click **+ New Savings Account**
3. Select Product: "Basic Savings Account"
4. Fill in:
   ```
   Submitted On: [Today's Date]
   Field Officer: John Smith
   External ID: SAV-2024-0001 (optional)
   ```
5. Click **Submit**
6. Click **Approve** (requires approval permission)
7. Click **Activate** to make the account live

### Making Deposits

1. Open the savings account
2. Click **Deposit**
3. Fill in:
   ```
   Transaction Date: [Today]
   Transaction Amount: $500.00
   Payment Type: Cash
   Receipt Number: DEP-001
   ```
4. Click **Submit**

### Making Withdrawals

1. Open the savings account
2. Click **Withdraw**
3. Fill in:
   ```
   Transaction Date: [Today]
   Transaction Amount: $100.00
   Payment Type: Cash
   Receipt Number: WD-001
   ```
4. Click **Submit**

### Account Transfers

Transfer between accounts within the bank:

1. Go to **Account Transfers**
2. Click **+ Create Standing Instruction** or **Make Transfer**
3. Fill in:
   ```
   From Account: Jane Doe - Savings (000001)
   To Account: Jane Doe - Checking (000002)
   Amount: $200.00
   Transfer Date: [Today]
   ```
4. Click **Submit**

---

## Loan Management

### Creating a Loan Application

1. Open client profile
2. Click **+ New Loan Account**
3. Select Product: "Personal Loan"
4. **Details**:
   ```
   Application Date: [Today]
   Principal: $10,000.00
   Loan Term: 24 months
   Repayment Frequency: Monthly
   First Repayment Date: [30 days from now]
   Interest Rate: 8.99%
   ```
5. Click **Submit**

### Loan Approval Workflow

1. **Submit Application** → Loan is in "Submitted and Pending Approval"
2. **Approve** → Loan Officer/Manager reviews and approves
3. **Disburse** → Funds are released to customer

### Disbursing a Loan

1. Open the approved loan
2. Click **Disburse**
3. Fill in:
   ```
   Disbursement Date: [Today]
   Transaction Amount: $10,000.00
   Payment Type: Bank Transfer
   Account Number: [Customer's external account]
   ```
4. Click **Submit**

### Processing Loan Repayments

1. Open the loan account
2. Click **Make Repayment**
3. Fill in:
   ```
   Transaction Date: [Today]
   Transaction Amount: $458.33
   Payment Type: ACH
   Receipt Number: PMT-001
   ```
4. Click **Submit**

### Handling Delinquent Loans

When a loan becomes delinquent:

1. Go to **Reports → Loan Reports → Aging Summary**
2. Review overdue loans
3. For each delinquent account:
   - Send reminder (Notes → Add Note)
   - Apply late fee if applicable
   - Escalate to collections if necessary

---

## Payment Processing

### Internal Transfers

For transfers between accounts at your bank:

1. Go to **Account Transfers → Make Account Transfer**
2. Select source and destination accounts
3. Enter amount and submit

### External Transfers (ACH)

For transfers to/from external banks:

1. **Prepare the ACH File**:
   ```bash
   # Using Moov ACH API
   curl -X POST http://localhost:8200/files/create \
     -H "Content-Type: application/json" \
     -d '{
       "immediateOrigin": "123456789",
       "immediateDestination": "987654321",
       "originName": "Your Bank Name",
       "destinationName": "Receiving Bank"
     }'
   ```

2. **Add Batch Entry**:
   ```bash
   curl -X POST http://localhost:8200/files/{fileID}/batches \
     -H "Content-Type: application/json" \
     -d '{
       "batchHeader": {
         "serviceClassCode": 220,
         "companyName": "Your Bank",
         "standardEntryClassCode": "PPD",
         "companyEntryDescription": "PAYMENT"
       }
     }'
   ```

3. **Add Entry Detail**:
   ```bash
   curl -X POST http://localhost:8200/files/{fileID}/batches/{batchID}/entries \
     -H "Content-Type: application/json" \
     -d '{
       "transactionCode": 22,
       "RDFIIdentification": "98765432",
       "checkDigit": "1",
       "DFIAccountNumber": "123456789",
       "amount": 50000,
       "individualName": "Jane Doe"
     }'
   ```

### Wire Transfers

For urgent, high-value transfers:

1. **Create Wire Message**:
   ```bash
   curl -X POST http://localhost:8201/files/create \
     -H "Content-Type: application/json" \
     -d '{
       "senderSupplied": {
         "formatVersion": "30",
         "testProductionCode": "T",
         "messageTypeCode": "1002"
       }
     }'
   ```

2. Wire transfers require:
   - Sender's bank ABA/routing number
   - Receiver's bank ABA/routing number
   - Beneficiary account details
   - Amount and purpose

---

## Compliance & Risk (Marble)

### Accessing Marble

1. Open http://localhost:3001
2. Login with: `jbe@zorg.com`
3. Check Firebase Auth emulator at http://localhost:4000 for password

### Setting Up Sanctions Screening

1. Go to **Rules** in Marble
2. Create a new rule:
   ```
   Name: OFAC Sanctions Check
   Trigger: On Customer Creation
   Condition: Match customer name against OFAC list
   Action: Flag for review if match > 80%
   ```

### Transaction Monitoring Rules

Create rules to detect suspicious activity:

1. **Large Cash Transactions**:
   ```
   Condition: Cash deposit > $10,000
   Action: Generate CTR (Currency Transaction Report)
   ```

2. **Structuring Detection**:
   ```
   Condition: Multiple deposits within 24 hours totaling > $10,000
   Action: Flag for SAR review
   ```

3. **Unusual Activity**:
   ```
   Condition: Transaction > 3x customer's average
   Action: Require additional verification
   ```

### Reviewing Alerts

1. Go to **Cases** in Marble
2. Review flagged transactions
3. Investigate and document findings
4. Escalate to compliance officer if needed
5. File SAR if suspicious activity confirmed

---

## ACH & Wire Transfers (Moov)

### Understanding Moov Services

| Service | Port | Purpose |
|---------|------|---------|
| ACH | 8200 | Domestic batch payments |
| Wire | 8201 | Real-time high-value transfers |
| ISO 20022 | 8202 | International message formatting |

### ACH Processing Workflow

1. **Origination**: Create ACH file with payment instructions
2. **Validation**: Moov validates file format
3. **Submission**: Send to Federal Reserve or clearing house
4. **Settlement**: Funds move between banks (1-2 business days)
5. **Confirmation**: Update Fineract with settlement status

### Common ACH Transaction Codes

| Code | Type | Description |
|------|------|-------------|
| 22 | Credit | Deposit to checking |
| 23 | Credit | Prenote for checking |
| 27 | Debit | Withdrawal from checking |
| 32 | Credit | Deposit to savings |
| 37 | Debit | Withdrawal from savings |

### Testing ACH Files

```bash
# Validate an ACH file
curl -X POST http://localhost:8200/files/create \
  -H "Content-Type: application/json" \
  -d @ach_file.json

# Get file contents
curl http://localhost:8200/files/{fileID}

# Validate file
curl -X POST http://localhost:8200/files/{fileID}/validate
```

---

## Reports & Analytics

### Standard Reports

1. Go to **Reports** in Mifos
2. Available report categories:
   - **Client Reports**: Client listing, activation summary
   - **Loan Reports**: Portfolio, aging, disbursements
   - **Savings Reports**: Deposits, withdrawals, balances
   - **Accounting Reports**: Trial balance, P&L, balance sheet

### Key Reports for Daily Operations

| Report | Frequency | Purpose |
|--------|-----------|---------|
| Daily Cash Position | Daily | Monitor liquidity |
| Loan Disbursement | Daily | Track new loans |
| Collection Sheet | Daily | Due payments |
| Trial Balance | Daily/Weekly | Account reconciliation |
| Aging Analysis | Weekly | Monitor delinquencies |
| Profitability | Monthly | Track earnings |

### Running a Report

1. Select report from Reports menu
2. Set parameters (date range, office, etc.)
3. Click **Run Report**
4. Export as PDF, Excel, or CSV

### Creating Custom Reports

1. Go to **Admin → Reports**
2. Click **+ Create Report**
3. Define:
   ```
   Report Name: Daily Transaction Summary
   Report Type: Table
   Report Category: Transaction
   SQL Query: [Your custom SQL]
   ```

---

## Going to Production

### Pre-Production Checklist

#### 1. Security Hardening

- [ ] Change all default passwords
- [ ] Enable HTTPS/TLS on all endpoints
- [ ] Set up firewall rules
- [ ] Enable audit logging
- [ ] Configure session timeouts
- [ ] Implement IP whitelisting

#### 2. Environment Configuration

```yaml
# production.env
FINERACT_SERVER_SSL_ENABLED=true
FINERACT_SERVER_PORT=443
FINERACT_LOGGING_LEVEL=WARN
SPRING_PROFILES_ACTIVE=production

# Database (use managed service)
FINERACT_HIKARI_JDBC_URL=jdbc:postgresql://prod-db.yourcloud.com:5432/fineract
FINERACT_HIKARI_USERNAME=fineract_prod
FINERACT_HIKARI_PASSWORD=[SECURE_PASSWORD]
```

#### 3. Database Migration

```bash
# Export development data
pg_dump -h localhost -U postgres fineract_tenants > tenants_backup.sql
pg_dump -h localhost -U postgres fineract_default > default_backup.sql

# Import to production (after sanitizing test data)
psql -h prod-db.yourcloud.com -U fineract_prod fineract_tenants < tenants_backup.sql
```

#### 4. Infrastructure Requirements

| Component | Development | Production |
|-----------|-------------|------------|
| CPU | 2 cores | 8+ cores |
| RAM | 4 GB | 32+ GB |
| Storage | 20 GB | 500+ GB SSD |
| Database | Local Docker | Managed PostgreSQL |
| Load Balancer | None | Required |
| CDN | None | Recommended |

### Cloud Deployment Options

#### AWS Deployment

```yaml
# docker-compose.production.yml
services:
  fineract:
    image: openmf/fineract:latest
    environment:
      - FINERACT_HIKARI_JDBC_URL=jdbc:postgresql://your-rds-endpoint:5432/fineract
      - AWS_REGION=us-east-1
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 4G
```

#### Kubernetes Deployment

```yaml
# fineract-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fineract
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fineract
  template:
    spec:
      containers:
      - name: fineract
        image: openmf/fineract:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
```

### Regulatory Compliance

#### US Banking Requirements

1. **Bank Secrecy Act (BSA)**
   - Implement CTR filing for cash > $10,000
   - SAR filing capability
   - Customer identification program (CIP)

2. **OFAC Compliance**
   - Integrate Marble with OFAC SDN list
   - Screen all new customers
   - Screen all international transfers

3. **FDIC/OCC Requirements**
   - Regular audits
   - Capital adequacy reporting
   - Stress testing

#### Integration Points

```
Your Bank System
├── Fineract (Core Banking)
│   └── API → Payment Hub
│              ├── → Marble (Compliance Check)
│              │      └── OFAC SDN List
│              │      └── Internal Rules
│              ├── → Moov ACH (Domestic)
│              │      └── Federal Reserve
│              └── → Moov Wire (Urgent)
│                     └── Fedwire
```

### Monitoring & Alerting

Set up monitoring for production:

1. **Application Monitoring**
   ```bash
   # Health check endpoints
   curl https://your-bank.com/fineract-provider/actuator/health
   ```

2. **Database Monitoring**
   - Connection pool usage
   - Query performance
   - Replication lag

3. **Business Metrics**
   - Transaction volume
   - Account openings
   - Loan disbursements
   - Error rates

### Backup Strategy

```bash
# Daily database backup
pg_dump -h prod-db -U postgres fineract_tenants | gzip > backup_$(date +%Y%m%d).sql.gz

# Upload to S3
aws s3 cp backup_$(date +%Y%m%d).sql.gz s3://your-backup-bucket/daily/

# Retain 30 days of daily, 12 months of monthly
```

### Disaster Recovery

1. **RTO (Recovery Time Objective)**: 4 hours
2. **RPO (Recovery Point Objective)**: 1 hour
3. **Hot Standby**: Secondary region with database replication
4. **Runbook**: Document all recovery procedures

---

## Quick Reference

### Common Tasks

| Task | Navigation |
|------|------------|
| Create Customer | Clients → + Create Client |
| Open Savings Account | Client Profile → + New Savings Account |
| Make Deposit | Savings Account → Deposit |
| Create Loan | Client Profile → + New Loan Account |
| Process Payment | Loan Account → Make Repayment |
| Transfer Funds | Account Transfers → Make Transfer |
| Run Report | Reports → Select Report |

### API Quick Reference

```bash
# Get all clients
curl -u mifos:password \
  -H "Fineract-Platform-TenantId: default" \
  http://localhost:8080/fineract-provider/api/v1/clients

# Get client details
curl -u mifos:password \
  -H "Fineract-Platform-TenantId: default" \
  http://localhost:8080/fineract-provider/api/v1/clients/{clientId}

# Get savings accounts
curl -u mifos:password \
  -H "Fineract-Platform-TenantId: default" \
  http://localhost:8080/fineract-provider/api/v1/savingsaccounts

# Make deposit
curl -X POST -u mifos:password \
  -H "Fineract-Platform-TenantId: default" \
  -H "Content-Type: application/json" \
  -d '{"transactionDate":"01 January 2024","transactionAmount":500,"paymentTypeId":1}' \
  http://localhost:8080/fineract-provider/api/v1/savingsaccounts/{accountId}/transactions?command=deposit
```

### Support Resources

- **Fineract Documentation**: https://fineract.apache.org/docs/
- **Mifos Community**: https://mifos.org/community/
- **GitHub Issues**: https://github.com/apache/fineract/issues
- **Mailing List**: dev@fineract.apache.org

---

## Appendix: Starting & Stopping Services

### Start All Services

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup

# Start Fineract & Mifos
cd mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql
docker-compose up -d

# Start Marble
cd ../../../marble
docker-compose -f docker-compose-dev.yaml --env-file .env.dev up -d

# Start Moov
cd ../moov
docker-compose up -d

# Start Payment Hub
cd ../payment-hub-ee
docker-compose up -d
```

### Stop All Services

```bash
cd /Users/reeceway/Desktop/fineract-mifos-setup

# Stop in reverse order
cd payment-hub-ee && docker-compose down
cd ../moov && docker-compose down
cd ../marble && docker-compose down
cd ../mifosplatform-25.03.22.RELEASE/docker/mifosx-postgresql && docker-compose down
```

### View Logs

```bash
# Fineract logs
docker logs -f mifosx-postgresql-fineract-server-1

# Marble logs
docker logs -f marble-api

# All containers status
docker ps -a
```