#!/bin/bash
# =============================================================================
# Elasticsearch Snapshot Script - MifosBank Production
# =============================================================================
# Schedule: Daily via cron
# Retention: 90 days
# Repository: Local filesystem (configure S3 for production)
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/.env" 2>/dev/null || true

# Elasticsearch settings
ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASSWORD="${ELASTICSEARCH_PASSWORD}"
ES_URL="http://${ES_HOST}:${ES_PORT}"

# Snapshot settings
SNAPSHOT_REPO="${ES_SNAPSHOT_REPO:-backup_repo}"
SNAPSHOT_NAME="snapshot_$(date +%Y%m%d_%H%M%S)"
RETENTION_DAYS="${ES_SNAPSHOT_RETENTION:-90}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
}

# Check Elasticsearch is accessible
log "Checking Elasticsearch connectivity..."
ES_HEALTH=$(curl -s -u "${ES_USER}:${ES_PASSWORD}" "${ES_URL}/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ES_HEALTH" ]; then
    error "Cannot connect to Elasticsearch at $ES_URL"
fi

log "Elasticsearch cluster status: $ES_HEALTH"

if [ "$ES_HEALTH" == "red" ]; then
    error "Elasticsearch cluster is in RED status - cannot create snapshot"
fi

# Check/Create snapshot repository
log "Checking snapshot repository: $SNAPSHOT_REPO"
REPO_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" -u "${ES_USER}:${ES_PASSWORD}" \
    "${ES_URL}/_snapshot/${SNAPSHOT_REPO}" 2>/dev/null)

if [ "$REPO_EXISTS" != "200" ]; then
    log "Creating snapshot repository..."

    # Create repository (filesystem type - for production use S3)
    curl -s -X PUT -u "${ES_USER}:${ES_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${ES_URL}/_snapshot/${SNAPSHOT_REPO}" \
        -d '{
            "type": "fs",
            "settings": {
                "location": "/usr/share/elasticsearch/backup",
                "compress": true,
                "max_snapshot_bytes_per_sec": "50mb",
                "max_restore_bytes_per_sec": "50mb"
            }
        }' > /dev/null

    # Verify repository
    VERIFY=$(curl -s -u "${ES_USER}:${ES_PASSWORD}" \
        "${ES_URL}/_snapshot/${SNAPSHOT_REPO}/_verify" 2>/dev/null)

    if echo "$VERIFY" | grep -q "error"; then
        error "Failed to verify snapshot repository"
    fi

    log "Snapshot repository created successfully"
else
    log "Snapshot repository exists"
fi

# Create snapshot
log "Creating snapshot: $SNAPSHOT_NAME"

SNAPSHOT_RESULT=$(curl -s -X PUT -u "${ES_USER}:${ES_PASSWORD}" \
    -H "Content-Type: application/json" \
    "${ES_URL}/_snapshot/${SNAPSHOT_REPO}/${SNAPSHOT_NAME}?wait_for_completion=true" \
    -d '{
        "indices": "*",
        "ignore_unavailable": true,
        "include_global_state": true,
        "metadata": {
            "taken_by": "backup-script",
            "taken_because": "scheduled backup"
        }
    }' 2>/dev/null)

# Check snapshot result
if echo "$SNAPSHOT_RESULT" | grep -q '"state":"SUCCESS"'; then
    log "Snapshot created successfully"
elif echo "$SNAPSHOT_RESULT" | grep -q '"state":"PARTIAL"'; then
    warn "Snapshot completed with partial success"
    echo "$SNAPSHOT_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print('Shards - Total:', d.get('snapshot',{}).get('shards',{}).get('total'), 'Failed:', d.get('snapshot',{}).get('shards',{}).get('failed'))"
else
    error "Snapshot failed: $SNAPSHOT_RESULT"
fi

# Get snapshot info
SNAPSHOT_INFO=$(curl -s -u "${ES_USER}:${ES_PASSWORD}" \
    "${ES_URL}/_snapshot/${SNAPSHOT_REPO}/${SNAPSHOT_NAME}" 2>/dev/null)

# Extract snapshot details
INDICES_COUNT=$(echo "$SNAPSHOT_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('snapshots',[{}])[0].get('indices',[])))" 2>/dev/null || echo "unknown")

# Cleanup old snapshots
log "Cleaning up snapshots older than $RETENTION_DAYS days..."

# List all snapshots
SNAPSHOTS=$(curl -s -u "${ES_USER}:${ES_PASSWORD}" \
    "${ES_URL}/_snapshot/${SNAPSHOT_REPO}/_all" 2>/dev/null)

# Calculate cutoff timestamp
CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" +%Y%m%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y%m%d)

# Get snapshots to delete
OLD_SNAPSHOTS=$(echo "$SNAPSHOTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
cutoff = int('$CUTOFF_DATE')
for snap in data.get('snapshots', []):
    name = snap.get('snapshot', '')
    # Extract date from snapshot name (format: snapshot_YYYYMMDD_HHMMSS)
    if name.startswith('snapshot_'):
        try:
            date_part = int(name.split('_')[1])
            if date_part < cutoff:
                print(name)
        except:
            pass
" 2>/dev/null || true)

DELETED_COUNT=0
for snap in $OLD_SNAPSHOTS; do
    log "Deleting old snapshot: $snap"
    curl -s -X DELETE -u "${ES_USER}:${ES_PASSWORD}" \
        "${ES_URL}/_snapshot/${SNAPSHOT_REPO}/${snap}" > /dev/null 2>&1
    ((DELETED_COUNT++)) || true
done

# Get current snapshot count
TOTAL_SNAPSHOTS=$(curl -s -u "${ES_USER}:${ES_PASSWORD}" \
    "${ES_URL}/_snapshot/${SNAPSHOT_REPO}/_all" 2>/dev/null | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin).get('snapshots',[])))" 2>/dev/null || echo "unknown")

# Summary
log "=========================================="
log "Elasticsearch Snapshot Complete"
log "=========================================="
log "Snapshot name: $SNAPSHOT_NAME"
log "Indices backed up: $INDICES_COUNT"
log "Old snapshots deleted: $DELETED_COUNT"
log "Total snapshots: $TOTAL_SNAPSHOTS"
log "=========================================="

exit 0
