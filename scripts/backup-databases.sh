#!/bin/bash

# =============================================================================
# MIFOS BANK-IN-A-BOX - DATABASE BACKUP SCRIPT
# =============================================================================
# Backs up all databases to timestamped files
# Run daily via cron: 0 2 * * * /path/to/backup-databases.sh
# =============================================================================

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/Users/reeceway/Desktop/fineract-mifos-setup/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DATE=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Load environment variables
cd "$(dirname "$0")/.."
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "=============================================="
echo "  Database Backup - $(date)"
echo "=============================================="

# =============================================================================
# FINERACT POSTGRESQL
# =============================================================================
echo ""
echo "Backing up Fineract PostgreSQL..."

FINERACT_BACKUP="$BACKUP_DIR/fineract_postgres_$DATE.sql.gz"

if docker ps | grep -q "postgresql"; then
    docker exec postgresql pg_dumpall -U postgres | gzip > "$FINERACT_BACKUP"
    if [ -f "$FINERACT_BACKUP" ]; then
        print_status "Fineract backup: $FINERACT_BACKUP ($(du -h "$FINERACT_BACKUP" | cut -f1))"
    else
        print_error "Fineract backup failed"
    fi
else
    print_error "Fineract PostgreSQL container not running"
fi

# =============================================================================
# PAYMENT HUB MYSQL
# =============================================================================
echo ""
echo "Backing up Payment Hub MySQL..."

PH_BACKUP="$BACKUP_DIR/paymenthub_mysql_$DATE.sql.gz"

if docker ps | grep -q "ph-mysql"; then
    docker exec ph-mysql mysqldump -u root -p"${PH_MYSQL_ROOT_PASSWORD}" --all-databases | gzip > "$PH_BACKUP"
    if [ -f "$PH_BACKUP" ]; then
        print_status "Payment Hub backup: $PH_BACKUP ($(du -h "$PH_BACKUP" | cut -f1))"
    else
        print_error "Payment Hub backup failed"
    fi
else
    print_error "Payment Hub MySQL container not running"
fi

# =============================================================================
# INFRASTRUCTURE MYSQL (Message Gateway)
# =============================================================================
echo ""
echo "Backing up Infrastructure MySQL..."

INFRA_MYSQL_BACKUP="$BACKUP_DIR/infra_mysql_$DATE.sql.gz"

if docker ps | grep -q "infra-mysql"; then
    docker exec infra-mysql mysqldump -u root -p"${MYSQL_PASSWORD}" --all-databases | gzip > "$INFRA_MYSQL_BACKUP"
    if [ -f "$INFRA_MYSQL_BACKUP" ]; then
        print_status "Infrastructure MySQL backup: $INFRA_MYSQL_BACKUP ($(du -h "$INFRA_MYSQL_BACKUP" | cut -f1))"
    else
        print_error "Infrastructure MySQL backup failed"
    fi
else
    echo "  Infrastructure MySQL container not running (skipping)"
fi

# =============================================================================
# KEYCLOAK POSTGRESQL
# =============================================================================
echo ""
echo "Backing up Keycloak PostgreSQL..."

KEYCLOAK_BACKUP="$BACKUP_DIR/keycloak_postgres_$DATE.sql.gz"

if docker ps | grep -q "keycloak-postgres"; then
    docker exec keycloak-postgres pg_dumpall -U keycloak | gzip > "$KEYCLOAK_BACKUP"
    if [ -f "$KEYCLOAK_BACKUP" ]; then
        print_status "Keycloak backup: $KEYCLOAK_BACKUP ($(du -h "$KEYCLOAK_BACKUP" | cut -f1))"
    else
        print_error "Keycloak backup failed"
    fi
else
    echo "  Keycloak PostgreSQL container not running (skipping)"
fi

# =============================================================================
# MARBLE POSTGRESQL
# =============================================================================
echo ""
echo "Backing up Marble PostgreSQL..."

MARBLE_BACKUP="$BACKUP_DIR/marble_postgres_$DATE.sql.gz"

if docker ps | grep -q "marble-postgres"; then
    docker exec marble-postgres pg_dumpall -U postgres | gzip > "$MARBLE_BACKUP"
    if [ -f "$MARBLE_BACKUP" ]; then
        print_status "Marble backup: $MARBLE_BACKUP ($(du -h "$MARBLE_BACKUP" | cut -f1))"
    else
        print_error "Marble backup failed"
    fi
else
    print_error "Marble PostgreSQL container not running"
fi

# =============================================================================
# ELASTICSEARCH SNAPSHOTS
# =============================================================================
echo ""
echo "Creating Elasticsearch index backup..."

ES_BACKUP="$BACKUP_DIR/elasticsearch_$DATE"

if docker ps | grep -q "mifos-elasticsearch"; then
    # Create snapshot repository if not exists
    curl -s -X PUT "localhost:9200/_snapshot/backup" \
        -H 'Content-Type: application/json' \
        -u "elastic:${ELASTICSEARCH_PASSWORD}" \
        -d '{
            "type": "fs",
            "settings": {
                "location": "/usr/share/elasticsearch/backup"
            }
        }' 2>/dev/null || true

    # Create snapshot
    curl -s -X PUT "localhost:9200/_snapshot/backup/snapshot_$DATE?wait_for_completion=true" \
        -u "elastic:${ELASTICSEARCH_PASSWORD}" 2>/dev/null

    print_status "Elasticsearch snapshot created: snapshot_$DATE"
else
    echo "  Elasticsearch container not running (skipping)"
fi

# =============================================================================
# CLEANUP OLD BACKUPS
# =============================================================================
echo ""
echo "Cleaning up backups older than $RETENTION_DAYS days..."

find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

print_status "Old backups cleaned up"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "=============================================="
echo "  Backup Complete"
echo "=============================================="
echo ""
echo "Backup directory: $BACKUP_DIR"
echo "Total size: $(du -sh "$BACKUP_DIR" | cut -f1)"
echo ""
ls -lh "$BACKUP_DIR"/*$DATE* 2>/dev/null || echo "No backups created for this run"
echo ""
echo "=============================================="
