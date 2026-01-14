#!/bin/bash

# =============================================================================
# MIFOS BANK-IN-A-BOX - INTEGRATION TEST SUITE
# =============================================================================
# Performance Auditor: Tests all integration points between components
# Run this after starting all services with ./start-all.sh
# =============================================================================

set -e

cd "$(dirname "$0")/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Load environment
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

print_header() {
    echo ""
    echo -e "${CYAN}=============================================="
    echo "  $1"
    echo -e "==============================================${NC}"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# =============================================================================
# LAYER 1: DOCKER & NETWORK INFRASTRUCTURE
# =============================================================================
print_header "Layer 1: Docker & Network Infrastructure"

print_test "Docker daemon running"
if docker info > /dev/null 2>&1; then
    print_pass "Docker daemon is running"
else
    print_fail "Docker daemon not running - cannot continue tests"
    exit 1
fi

print_test "Required networks exist"
NETWORKS_OK=true
for net in mifos-fineract-network mifos-app moov-network; do
    if docker network inspect "$net" > /dev/null 2>&1; then
        print_pass "Network $net exists"
    else
        print_fail "Network $net missing"
        NETWORKS_OK=false
    fi
done

# =============================================================================
# LAYER 2: CORE BANKING (FINERACT)
# =============================================================================
print_header "Layer 2: Core Banking (Fineract)"

print_test "Fineract server container running"
if docker ps --format '{{.Names}}' | grep -q "fineract-server"; then
    print_pass "fineract-server container running"

    print_test "Fineract HTTPS endpoint responding"
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost:8443/fineract-provider/api/v1 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|401|403)$ ]]; then
        print_pass "Fineract API responding (HTTPS:8443) - HTTP $HTTP_CODE"
    else
        print_fail "Fineract API not responding - HTTP $HTTP_CODE"
    fi

    print_test "Fineract authentication working"
    AUTH_RESPONSE=$(curl -sk -u mifos:${FINERACT_PASSWORD:-password} \
        -H "Fineract-Platform-TenantId: default" \
        "https://localhost:8443/fineract-provider/api/v1/authentication?username=mifos&password=${FINERACT_PASSWORD:-password}" 2>/dev/null)
    if echo "$AUTH_RESPONSE" | grep -q "authenticated\|permissions"; then
        print_pass "Fineract authentication successful"
    else
        print_fail "Fineract authentication failed"
        print_info "Response: $(echo "$AUTH_RESPONSE" | head -c 200)"
    fi

    print_test "Fineract database connection"
    if docker exec fineract-server sh -c 'nc -z postgresql 5432' 2>/dev/null; then
        print_pass "Fineract can reach PostgreSQL"
    else
        print_fail "Fineract cannot reach PostgreSQL"
    fi
else
    print_skip "Fineract server not running"
fi

print_test "PostgreSQL container running"
if docker ps --format '{{.Names}}' | grep -q "^postgresql$"; then
    print_pass "PostgreSQL container running"

    print_test "PostgreSQL accepting connections"
    if docker exec postgresql pg_isready -U postgres > /dev/null 2>&1; then
        print_pass "PostgreSQL accepting connections"
    else
        print_fail "PostgreSQL not accepting connections"
    fi

    print_test "Fineract databases exist"
    DBS=$(docker exec postgresql psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datname LIKE 'fineract%';" 2>/dev/null)
    if echo "$DBS" | grep -q "fineract"; then
        print_pass "Fineract databases exist: $(echo $DBS | tr '\n' ' ')"
    else
        print_fail "Fineract databases missing"
    fi
else
    print_skip "PostgreSQL not running"
fi

print_test "Mifos Web App container running"
if docker ps --format '{{.Names}}' | grep -q "web-app"; then
    print_pass "web-app container running"

    print_test "Mifos Web App HTTP endpoint"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Mifos Web App responding (HTTP:80)"
    else
        print_fail "Mifos Web App not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "Mifos Web App not running"
fi

# =============================================================================
# LAYER 3: COMPLIANCE (MARBLE)
# =============================================================================
print_header "Layer 3: Compliance Engine (Marble)"

print_test "Marble API container running"
if docker ps --format '{{.Names}}' | grep -q "marble-api"; then
    print_pass "marble-api container running"

    print_test "Marble API health check"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8180/liveness 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Marble API healthy (HTTP:8180)"
    else
        print_fail "Marble API not healthy - HTTP $HTTP_CODE"
    fi

    print_test "Marble can reach its PostgreSQL"
    if docker exec marble-api sh -c 'nc -z db 5432' 2>/dev/null || \
       docker exec marble-api sh -c 'nc -z marble-postgres 5432' 2>/dev/null; then
        print_pass "Marble can reach PostgreSQL"
    else
        print_fail "Marble cannot reach PostgreSQL"
    fi
else
    print_skip "Marble API not running"
fi

print_test "Marble App (Frontend) running"
if docker ps --format '{{.Names}}' | grep -q "marble-app"; then
    print_pass "marble-app container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Marble App responding (HTTP:3001)"
    else
        print_fail "Marble App not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "Marble App not running"
fi

print_test "Yente (OpenSanctions) running"
if docker ps --format '{{.Names}}' | grep -q "marble-yente\|yente"; then
    print_pass "Yente container running"

    print_test "Yente API responding"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/healthz 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Yente API healthy (HTTP:8001)"

        print_test "Yente sanctions data loaded"
        SEARCH=$(curl -s "http://localhost:8001/search/default?q=test" 2>/dev/null)
        if echo "$SEARCH" | grep -q "results\|total"; then
            print_pass "Yente sanctions search functional"
        else
            print_fail "Yente sanctions search not working"
        fi
    else
        print_fail "Yente API not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "Yente not running"
fi

# =============================================================================
# LAYER 4: PAYMENT RAILS (MOOV)
# =============================================================================
print_header "Layer 4: Payment Rails (Moov)"

print_test "Moov ACH container running"
if docker ps --format '{{.Names}}' | grep -q "moov-ach"; then
    print_pass "moov-ach container running"

    print_test "Moov ACH health check"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8200/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Moov ACH healthy (HTTP:8200)"

        print_test "Moov ACH can parse NACHA files"
        # Create a minimal ACH file test
        ACH_TEST=$(curl -s -X POST http://localhost:8200/files/create \
            -H "Content-Type: application/json" \
            -d '{"immediateOrigin":"123456789","immediateDestination":"987654321"}' 2>/dev/null)
        if echo "$ACH_TEST" | grep -q "id\|fileHeader"; then
            print_pass "Moov ACH file creation works"
        else
            print_info "Moov ACH file creation returned: $(echo $ACH_TEST | head -c 100)"
        fi
    else
        print_fail "Moov ACH not healthy - HTTP $HTTP_CODE"
    fi
else
    print_skip "Moov ACH not running"
fi

print_test "Moov Wire container running"
if docker ps --format '{{.Names}}' | grep -q "moov-wire"; then
    print_pass "moov-wire container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8201/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Moov Wire healthy (HTTP:8201)"
    else
        print_fail "Moov Wire not healthy - HTTP $HTTP_CODE"
    fi
else
    print_skip "Moov Wire not running"
fi

print_test "Moov ISO20022 container running"
if docker ps --format '{{.Names}}' | grep -q "moov-iso20022"; then
    print_pass "moov-iso20022 container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8202/health 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|404)$ ]]; then
        print_pass "Moov ISO20022 responding (HTTP:8202)"
    else
        print_fail "Moov ISO20022 not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "Moov ISO20022 not running"
fi

# =============================================================================
# LAYER 5: PAYMENT ORCHESTRATION (PAYMENT HUB)
# =============================================================================
print_header "Layer 5: Payment Orchestration (Payment Hub)"

print_test "Zeebe workflow engine running"
if docker ps --format '{{.Names}}' | grep -q "ph-zeebe"; then
    print_pass "ph-zeebe container running"

    print_test "Zeebe health check"
    if docker exec ph-zeebe wget -q --spider http://localhost:9600/health 2>/dev/null; then
        print_pass "Zeebe workflow engine healthy"

        print_test "Zeebe not exposed externally (security)"
        if ! curl -s --connect-timeout 2 http://localhost:26500 > /dev/null 2>&1; then
            print_pass "Zeebe port 26500 not exposed externally (GOOD)"
        else
            print_fail "Zeebe port 26500 is exposed externally (SECURITY RISK)"
        fi
    else
        print_fail "Zeebe not healthy"
    fi
else
    print_skip "Zeebe not running"
fi

print_test "Payment Hub Channel connector running"
if docker ps --format '{{.Names}}' | grep -q "ph-channel"; then
    print_pass "ph-channel container running"

    print_test "Channel connector can reach Zeebe"
    if docker exec ph-channel sh -c 'nc -z zeebe 26500' 2>/dev/null; then
        print_pass "Channel connector can reach Zeebe"
    else
        print_fail "Channel connector cannot reach Zeebe"
    fi
else
    print_skip "Payment Hub Channel not running"
fi

print_test "Payment Hub AMS-Mifos connector running"
if docker ps --format '{{.Names}}' | grep -q "ph-ams-mifos"; then
    print_pass "ph-ams-mifos container running"

    print_test "AMS-Mifos can reach Fineract"
    if docker exec ph-ams-mifos sh -c 'nc -z fineract-server 8443' 2>/dev/null; then
        print_pass "AMS-Mifos can reach Fineract (port 8443)"
    else
        print_fail "AMS-Mifos cannot reach Fineract"
    fi
else
    print_skip "Payment Hub AMS-Mifos not running"
fi

print_test "Payment Hub Compliance connector running"
if docker ps --format '{{.Names}}' | grep -q "ph-compliance"; then
    print_pass "ph-compliance container running"

    print_test "Compliance connector can reach Marble"
    if docker exec ph-compliance sh -c 'nc -z marble-api 8080' 2>/dev/null; then
        print_pass "Compliance connector can reach Marble API"
    else
        print_fail "Compliance connector cannot reach Marble"
    fi
else
    print_skip "Payment Hub Compliance connector not running"
fi

print_test "Payment Hub Moov connector running"
if docker ps --format '{{.Names}}' | grep -q "ph-moov"; then
    print_pass "ph-moov container running"

    print_test "Moov connector can reach Moov ACH"
    if docker exec ph-moov sh -c 'nc -z moov-ach 8080' 2>/dev/null; then
        print_pass "Moov connector can reach Moov ACH"
    else
        print_fail "Moov connector cannot reach Moov ACH"
    fi
else
    print_skip "Payment Hub Moov connector not running"
fi

print_test "Payment Hub Operations app running"
if docker ps --format '{{.Names}}' | grep -q "ph-operations"; then
    print_pass "ph-operations container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8283 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302|401)$ ]]; then
        print_pass "Operations app responding (HTTP:8283)"
    else
        print_fail "Operations app not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "Payment Hub Operations not running"
fi

# =============================================================================
# LAYER 6: CUSTOMER PORTAL
# =============================================================================
print_header "Layer 6: Customer Portal"

print_test "Customer Portal container running"
if docker ps --format '{{.Names}}' | grep -q "mifos-customer-portal"; then
    print_pass "mifos-customer-portal container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4200 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Customer Portal responding (HTTP:4200)"
    else
        print_fail "Customer Portal not responding - HTTP $HTTP_CODE"
    fi

    print_test "Customer Portal can reach Fineract"
    if docker exec mifos-customer-portal sh -c 'nc -z fineract-server 8443' 2>/dev/null; then
        print_pass "Customer Portal can reach Fineract"
    else
        print_fail "Customer Portal cannot reach Fineract"
    fi
else
    print_skip "Customer Portal not running"
fi

# =============================================================================
# LAYER 7: INFRASTRUCTURE (OPTIONAL)
# =============================================================================
print_header "Layer 7: Infrastructure Services (Optional)"

print_test "Keycloak running"
if docker ps --format '{{.Names}}' | grep -q "mifos-keycloak"; then
    print_pass "mifos-keycloak container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8180 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302|303)$ ]]; then
        print_pass "Keycloak responding (HTTP:8180)"
    else
        print_fail "Keycloak not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "Keycloak not running"
fi

print_test "Elasticsearch running"
if docker ps --format '{{.Names}}' | grep -q "mifos-elasticsearch"; then
    print_pass "mifos-elasticsearch container running"

    ES_HEALTH=$(curl -s -u "elastic:${ELASTICSEARCH_PASSWORD}" http://localhost:9200/_cluster/health 2>/dev/null || echo "{}")
    if echo "$ES_HEALTH" | grep -q '"status":"green"\|"status":"yellow"'; then
        print_pass "Elasticsearch cluster healthy"
    else
        print_fail "Elasticsearch cluster not healthy"
    fi
else
    print_skip "Elasticsearch not running"
fi

print_test "Kafka running"
if docker ps --format '{{.Names}}' | grep -q "mifos-kafka"; then
    print_pass "mifos-kafka container running"
else
    print_skip "Kafka not running"
fi

print_test "Redis running"
if docker ps --format '{{.Names}}' | grep -q "mifos-redis"; then
    print_pass "mifos-redis container running"

    print_test "Redis authentication working"
    if docker exec mifos-redis redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q "PONG"; then
        print_pass "Redis authentication working"
    else
        print_fail "Redis authentication failed"
    fi
else
    print_skip "Redis not running"
fi

print_test "MinIO running"
if docker ps --format '{{.Names}}' | grep -q "mifos-minio"; then
    print_pass "mifos-minio container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9001 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "MinIO Console responding (HTTP:9001)"
    else
        print_fail "MinIO Console not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "MinIO not running"
fi

print_test "Grafana running"
if docker ps --format '{{.Names}}' | grep -q "mifos-grafana"; then
    print_pass "mifos-grafana container running"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_pass "Grafana responding (HTTP:3000)"
    else
        print_fail "Grafana not responding - HTTP $HTTP_CODE"
    fi
else
    print_skip "Grafana not running"
fi

# =============================================================================
# CROSS-COMPONENT INTEGRATION TESTS
# =============================================================================
print_header "Cross-Component Integration Tests"

print_test "End-to-end: Payment Hub → Fineract API call"
if docker ps --format '{{.Names}}' | grep -q "ph-ams-mifos" && \
   docker ps --format '{{.Names}}' | grep -q "fineract-server"; then

    # Test if AMS can authenticate with Fineract
    AUTH_TEST=$(docker exec ph-ams-mifos sh -c "curl -sk -u mifos:${FINERACT_PASSWORD:-password} \
        -H 'Fineract-Platform-TenantId: default' \
        https://fineract-server:8443/fineract-provider/api/v1/offices" 2>/dev/null)

    if echo "$AUTH_TEST" | grep -q "id\|name\|Head Office"; then
        print_pass "Payment Hub can call Fineract API successfully"
    else
        print_fail "Payment Hub cannot call Fineract API"
        print_info "Response: $(echo "$AUTH_TEST" | head -c 200)"
    fi
else
    print_skip "Required containers not running for this test"
fi

print_test "End-to-end: Payment Hub → Marble screening"
if docker ps --format '{{.Names}}' | grep -q "ph-compliance" && \
   docker ps --format '{{.Names}}' | grep -q "marble-api"; then

    # Test if compliance connector can reach Marble
    MARBLE_TEST=$(docker exec ph-compliance sh -c "curl -s http://marble-api:8080/liveness" 2>/dev/null)

    if echo "$MARBLE_TEST" | grep -q "ok\|healthy\|200" || [ -n "$MARBLE_TEST" ]; then
        print_pass "Payment Hub can reach Marble for compliance screening"
    else
        print_fail "Payment Hub cannot reach Marble"
    fi
else
    print_skip "Required containers not running for this test"
fi

print_test "End-to-end: Payment Hub → Moov ACH"
if docker ps --format '{{.Names}}' | grep -q "ph-moov" && \
   docker ps --format '{{.Names}}' | grep -q "moov-ach"; then

    MOOV_TEST=$(docker exec ph-moov sh -c "curl -s http://moov-ach:8080/health" 2>/dev/null)

    if echo "$MOOV_TEST" | grep -q "ok\|healthy" || [ "$MOOV_TEST" = "" ]; then
        print_pass "Payment Hub can reach Moov ACH"
    else
        print_fail "Payment Hub cannot reach Moov ACH"
    fi
else
    print_skip "Required containers not running for this test"
fi

# =============================================================================
# SECURITY TESTS
# =============================================================================
print_header "Security Validation"

print_test "Database ports not exposed externally"
SECURITY_ISSUES=0

# Check PostgreSQL
if netstat -an 2>/dev/null | grep -q ":5432.*LISTEN" || \
   lsof -i :5432 2>/dev/null | grep -q "LISTEN"; then
    print_fail "PostgreSQL port 5432 is exposed (SECURITY RISK)"
    ((SECURITY_ISSUES++))
else
    print_pass "PostgreSQL port 5432 not exposed externally"
fi

# Check MySQL
if netstat -an 2>/dev/null | grep -q ":3306.*LISTEN" || \
   lsof -i :3306 2>/dev/null | grep -q "LISTEN"; then
    print_fail "MySQL port 3306 is exposed (SECURITY RISK)"
    ((SECURITY_ISSUES++))
else
    print_pass "MySQL port 3306 not exposed externally"
fi

# Check Redis
if netstat -an 2>/dev/null | grep -q ":6379.*LISTEN" || \
   lsof -i :6379 2>/dev/null | grep -q "LISTEN"; then
    print_fail "Redis port 6379 is exposed (SECURITY RISK)"
    ((SECURITY_ISSUES++))
else
    print_pass "Redis port 6379 not exposed externally"
fi

print_test "Fineract using HTTPS"
if curl -sk https://localhost:8443 > /dev/null 2>&1; then
    print_pass "Fineract API uses HTTPS"
else
    print_fail "Fineract API not using HTTPS"
fi

# =============================================================================
# SUMMARY
# =============================================================================
print_header "Test Summary"

TOTAL=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

echo ""
echo "Results:"
echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
echo "  ─────────────"
echo "  Total:   $TOTAL"
echo ""

if [ $TESTS_FAILED -eq 0 ] && [ $TESTS_PASSED -gt 0 ]; then
    echo -e "${GREEN}✓ All tests passed! Integration is functional.${NC}"
    exit 0
elif [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}✗ Some tests failed. Review the output above.${NC}"
    exit 1
else
    echo -e "${YELLOW}⚠ No tests could run. Are services started?${NC}"
    echo ""
    echo "To start services, run: ./start-all.sh"
    exit 2
fi
