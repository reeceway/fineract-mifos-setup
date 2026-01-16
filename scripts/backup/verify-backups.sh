#!/bin/bash
# =============================================================================
# Backup Verification Script - MifosBank Production
# =============================================================================
# Verifies backup integrity using checksums
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Backup directory
BACKUP_BASE="${BACKUP_DIR:-/backups}"
VERIFICATION_REPORT="$BACKUP_BASE/verification_$(date +%Y%m%d).txt"

# Logging
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$VERIFICATION_REPORT"
}

error_count=0
verified_count=0

log "=========================================="
log "Backup Verification Report"
log "=========================================="
log "Date: $(date)"
log ""

verify_checksums() {
    local dir="$1"
    local name="$2"

    log "Verifying $name backups in $dir..."

    if [ ! -d "$dir" ]; then
        log "  Directory not found: $dir"
        return
    fi

    for checksum_file in "$dir"/*.sha256; do
        if [ ! -f "$checksum_file" ]; then
            continue
        fi

        backup_file="${checksum_file%.sha256}"
        backup_name=$(basename "$backup_file")

        if [ -f "$backup_file" ]; then
            # Verify checksum
            if cd "$(dirname "$checksum_file")" && sha256sum -c "$(basename "$checksum_file")" > /dev/null 2>&1; then
                log "  ✓ $backup_name: VERIFIED"
                ((verified_count++))
            else
                log "  ✗ $backup_name: CHECKSUM MISMATCH"
                ((error_count++))
            fi
        else
            log "  ✗ $backup_name: FILE MISSING"
            ((error_count++))
        fi
    done
}

# Verify all backup types
verify_checksums "$BACKUP_BASE/postgres" "PostgreSQL"
verify_checksums "$BACKUP_BASE/mysql" "MySQL"
verify_checksums "$BACKUP_BASE/vault" "Vault"

# Check Elasticsearch snapshots
log ""
log "Checking Elasticsearch snapshots..."

ES_URL="${ES_URL:-http://localhost:9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASSWORD="${ELASTICSEARCH_PASSWORD:-}"
ES_REPO="${ES_SNAPSHOT_REPO:-backup_repo}"

if [ -n "$ES_PASSWORD" ]; then
    SNAP_COUNT=$(curl -s -u "${ES_USER}:${ES_PASSWORD}" \
        "${ES_URL}/_snapshot/${ES_REPO}/_all" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(len([s for s in d.get('snapshots',[]) if s.get('state')=='SUCCESS']))" 2>/dev/null || echo "0")

    log "  Elasticsearch snapshots (SUCCESS): $SNAP_COUNT"
    if [ "$SNAP_COUNT" -gt 0 ]; then
        ((verified_count++))
    else
        log "  WARNING: No successful Elasticsearch snapshots found"
    fi
else
    log "  SKIPPED: Elasticsearch password not set"
fi

# Check backup age
log ""
log "Checking backup freshness..."

check_freshness() {
    local dir="$1"
    local name="$2"
    local max_hours="$3"

    if [ ! -d "$dir" ]; then
        return
    fi

    latest=$(find "$dir" -type f \( -name "*.gz" -o -name "*.enc" \) -mmin -$((max_hours * 60)) 2>/dev/null | head -1)

    if [ -n "$latest" ]; then
        age_hours=$(( ($(date +%s) - $(stat -f %m "$latest" 2>/dev/null || stat -c %Y "$latest" 2>/dev/null || echo 0)) / 3600 ))
        log "  $name: Latest backup is ${age_hours}h old (threshold: ${max_hours}h) ✓"
    else
        log "  $name: No backup within ${max_hours}h ✗"
        ((error_count++))
    fi
}

check_freshness "$BACKUP_BASE/postgres" "PostgreSQL" 12
check_freshness "$BACKUP_BASE/mysql" "MySQL" 12
check_freshness "$BACKUP_BASE/vault" "Vault" 48

# Summary
log ""
log "=========================================="
log "VERIFICATION SUMMARY"
log "=========================================="
log "Verified: $verified_count"
log "Errors: $error_count"
log "Report: $VERIFICATION_REPORT"
log "=========================================="

if [ "$error_count" -gt 0 ]; then
    log "STATUS: FAILED - Some backups need attention"
    exit 1
else
    log "STATUS: PASSED - All backups verified"
    exit 0
fi
