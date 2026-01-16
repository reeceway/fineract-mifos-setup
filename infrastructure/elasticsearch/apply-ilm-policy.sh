#!/bin/bash
# =============================================================================
# Apply Elasticsearch ILM Policy and Index Templates
# For 7-year log retention per BSA/GLBA requirements
# =============================================================================

set -euo pipefail

ES_HOST="${ELASTICSEARCH_HOST:-https://localhost:9200}"
ES_USER="${ELASTICSEARCH_USER:-elastic}"
ES_PASS="${ELASTICSEARCH_PASSWORD:-}"

# Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch..."
until curl -s -u "${ES_USER}:${ES_PASS}" -k "${ES_HOST}/_cluster/health" | grep -q '"status":"green"\|"status":"yellow"'; do
    sleep 5
    echo "Waiting for Elasticsearch cluster..."
done
echo "Elasticsearch is ready"

# Apply ILM policy
echo "Applying 7-year retention ILM policy..."
curl -s -X PUT "${ES_HOST}/_ilm/policy/banking-audit-7year" \
    -u "${ES_USER}:${ES_PASS}" \
    -k \
    -H 'Content-Type: application/json' \
    -d @"$(dirname "$0")/ilm-policy-7year.json"
echo ""

# Create index template that uses the ILM policy
echo "Creating index template for audit logs..."
curl -s -X PUT "${ES_HOST}/_index_template/banking-audit-logs" \
    -u "${ES_USER}:${ES_PASS}" \
    -k \
    -H 'Content-Type: application/json' \
    -d '{
  "index_patterns": ["audit-*", "banking-*", "fineract-*", "mifos-*", "compliance-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "banking-audit-7year",
      "index.lifecycle.rollover_alias": "banking-audit"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "level": { "type": "keyword" },
        "service": { "type": "keyword" },
        "user": { "type": "keyword" },
        "action": { "type": "keyword" },
        "client_ip": { "type": "ip" },
        "message": { "type": "text" },
        "transaction_id": { "type": "keyword" },
        "account_id": { "type": "keyword" },
        "customer_id": { "type": "keyword" }
      }
    }
  },
  "_meta": {
    "description": "Index template for banking audit logs with 7-year retention",
    "regulatory_requirement": "BSA 31 CFR 103.38, GLBA Safeguards Rule"
  }
}'
echo ""

# Create initial index with rollover alias
echo "Creating initial audit index with rollover alias..."
curl -s -X PUT "${ES_HOST}/banking-audit-000001" \
    -u "${ES_USER}:${ES_PASS}" \
    -k \
    -H 'Content-Type: application/json' \
    -d '{
  "aliases": {
    "banking-audit": {
      "is_write_index": true
    }
  }
}'
echo ""

# Verify
echo ""
echo "Verifying ILM policy..."
curl -s "${ES_HOST}/_ilm/policy/banking-audit-7year" \
    -u "${ES_USER}:${ES_PASS}" \
    -k | jq '.banking-audit-7year.policy.phases | keys'

echo ""
echo "ILM policy applied successfully. Logs matching patterns:"
echo "  - audit-*"
echo "  - banking-*"
echo "  - fineract-*"
echo "  - mifos-*"
echo "  - compliance-*"
echo "will be retained for 7 years per BSA/GLBA requirements."
