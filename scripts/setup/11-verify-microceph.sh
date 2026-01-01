#!/usr/bin/env bash
#
# Script: 11-verify-microceph.sh
# Purpose: Verify MicroCeph installation with PVC tests
# Prerequisites: MicroCeph installed (run 10-enable-microceph.sh first)
# Author: VX Home Infrastructure
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

print_header "MicroCeph Verification"

# Get kubectl command
KUBECTL=$(get_kubectl) || exit 1

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1"
    local result="$2"

    if [[ "$result" == "pass" ]]; then
        log_success "✓ $name"
        ((TESTS_PASSED++))
    else
        log_error "✗ $name"
        ((TESTS_FAILED++))
    fi
}

# ============================================================================
# Test 1: MicroCeph Status
# ============================================================================

log_step "Checking MicroCeph status..."

if microceph status 2>/dev/null | grep -q "ceph-mon"; then
    run_test "MicroCeph cluster running" "pass"
else
    run_test "MicroCeph cluster running" "fail"
fi

echo ""

# ============================================================================
# Test 2: Ceph Health
# ============================================================================

log_step "Checking Ceph health..."

CEPH_HEALTH=$(microceph.ceph health 2>/dev/null || echo "ERROR")

if [[ "$CEPH_HEALTH" == "HEALTH_OK" ]] || [[ "$CEPH_HEALTH" == "HEALTH_WARN" ]]; then
    run_test "Ceph health: $CEPH_HEALTH" "pass"
    if [[ "$CEPH_HEALTH" == "HEALTH_WARN" ]]; then
        log_warn "Warning details:"
        microceph.ceph health detail 2>/dev/null | head -5
    fi
else
    run_test "Ceph health: $CEPH_HEALTH" "fail"
fi

echo ""

# ============================================================================
# Test 3: OSD Status
# ============================================================================

log_step "Checking OSD status..."

OSD_COUNT=$(microceph.ceph osd stat 2>/dev/null | grep -oP '\d+(?= osds:)' || echo "0")

if [[ "$OSD_COUNT" -gt 0 ]]; then
    run_test "OSD count: $OSD_COUNT" "pass"
    log_info "OSD tree:"
    microceph.ceph osd tree 2>/dev/null | head -10
else
    run_test "OSD count: $OSD_COUNT" "fail"
fi

echo ""

# ============================================================================
# Test 4: StorageClass Availability
# ============================================================================

log_step "Checking StorageClasses..."

if $KUBECTL get sc ceph-rbd &>/dev/null; then
    run_test "ceph-rbd StorageClass exists" "pass"
else
    run_test "ceph-rbd StorageClass exists" "fail"
fi

if $KUBECTL get sc cephfs &>/dev/null; then
    run_test "cephfs StorageClass exists" "pass"
else
    run_test "cephfs StorageClass exists" "fail"
fi

echo ""

# ============================================================================
# Test 5: CSI Pods Running
# ============================================================================

log_step "Checking CSI pods..."

RBD_PODS=$($KUBECTL get pods -n rook-ceph -l app=csi-rbdplugin --no-headers 2>/dev/null | grep -c Running || echo "0")
CEPHFS_PODS=$($KUBECTL get pods -n rook-ceph -l app=csi-cephfsplugin --no-headers 2>/dev/null | grep -c Running || echo "0")

if [[ "$RBD_PODS" -gt 0 ]]; then
    run_test "RBD CSI pods running: $RBD_PODS" "pass"
else
    run_test "RBD CSI pods running" "fail"
fi

if [[ "$CEPHFS_PODS" -gt 0 ]]; then
    run_test "CephFS CSI pods running: $CEPHFS_PODS" "pass"
else
    run_test "CephFS CSI pods running" "fail"
fi

echo ""

# ============================================================================
# Test 6: PVC Test - RBD (ReadWriteOnce)
# ============================================================================

log_step "Testing RBD PVC (ReadWriteOnce)..."

TEST_PVC_RBD="test-rbd-$(date +%s)"

# Create test PVC
$KUBECTL apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TEST_PVC_RBD
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
EOF

# Wait for binding
log_info "Waiting for PVC to bind..."
TIMEOUT=60
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    STATUS=$($KUBECTL get pvc "$TEST_PVC_RBD" -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$STATUS" == "Bound" ]]; then
        break
    fi
    sleep 5
    ((ELAPSED+=5))
done

STATUS=$($KUBECTL get pvc "$TEST_PVC_RBD" -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [[ "$STATUS" == "Bound" ]]; then
    run_test "RBD PVC binding" "pass"
else
    run_test "RBD PVC binding (status: $STATUS)" "fail"
    log_info "PVC events:"
    $KUBECTL describe pvc "$TEST_PVC_RBD" -n default | grep -A 5 "Events:" || true
fi

# Cleanup
$KUBECTL delete pvc "$TEST_PVC_RBD" -n default --ignore-not-found &>/dev/null

echo ""

# ============================================================================
# Test 7: PVC Test - CephFS (ReadWriteMany)
# ============================================================================

log_step "Testing CephFS PVC (ReadWriteMany)..."

TEST_PVC_CEPHFS="test-cephfs-$(date +%s)"

# Create test PVC
$KUBECTL apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TEST_PVC_CEPHFS
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: cephfs
  resources:
    requests:
      storage: 1Gi
EOF

# Wait for binding
log_info "Waiting for PVC to bind..."
TIMEOUT=60
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    STATUS=$($KUBECTL get pvc "$TEST_PVC_CEPHFS" -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$STATUS" == "Bound" ]]; then
        break
    fi
    sleep 5
    ((ELAPSED+=5))
done

STATUS=$($KUBECTL get pvc "$TEST_PVC_CEPHFS" -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [[ "$STATUS" == "Bound" ]]; then
    run_test "CephFS PVC binding" "pass"
else
    run_test "CephFS PVC binding (status: $STATUS)" "fail"
    log_info "PVC events:"
    $KUBECTL describe pvc "$TEST_PVC_CEPHFS" -n default | grep -A 5 "Events:" || true
fi

# Cleanup
$KUBECTL delete pvc "$TEST_PVC_CEPHFS" -n default --ignore-not-found &>/dev/null

echo ""

# ============================================================================
# Test 8: OSD Storage Backend
# ============================================================================

log_step "Checking OSD storage backend..."

# Detect storage type by checking what backs the OSD
# Loop device: /var/lib/microceph-loop/osd.img exists
# Dedicated disk: OSD backed by real block device

if [[ -f "/var/lib/microceph-loop/osd.img" ]]; then
    # Loop device setup detected
    log_info "Storage type: Loop device"

    if systemctl is-enabled microceph-loop.service &>/dev/null; then
        run_test "microceph-loop.service enabled" "pass"
    else
        run_test "microceph-loop.service enabled" "fail"
        log_warn "Loop device may not survive reboot!"
    fi

    SIZE=$(du -h /var/lib/microceph-loop/osd.img | awk '{print $1}')
    run_test "Loop file exists ($SIZE)" "pass"
else
    # Dedicated disk setup - check OSD devices
    log_info "Storage type: Dedicated disk"

    # Get OSD device info from microceph
    OSD_DISKS=$(microceph disk list 2>/dev/null || echo "")
    if [[ -n "$OSD_DISKS" ]]; then
        run_test "Dedicated disk(s) configured" "pass"
        log_info "OSD disk(s):"
        echo "$OSD_DISKS" | head -5
    else
        run_test "Dedicated disk(s) configured" "fail"
    fi

    # Verify OSD is active
    OSD_UP=$(microceph.ceph osd stat 2>/dev/null | grep -oP '\d+(?= up)' || echo "0")
    if [[ "$OSD_UP" -gt 0 ]]; then
        run_test "OSD(s) up: $OSD_UP" "pass"
    else
        run_test "OSD(s) up" "fail"
    fi
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

print_header "Verification Summary"

TOTAL=$((TESTS_PASSED + TESTS_FAILED))

if [[ $TESTS_FAILED -eq 0 ]]; then
    log_success "All $TOTAL tests passed!"
    echo ""
    log_info "MicroCeph is ready for use."
    echo ""
    log_info "Available storage classes:"
    $KUBECTL get sc | grep -E "^(NAME|ceph)"
    echo ""
    log_info "Next steps:"
    echo "  1. Run: sudo ./scripts/setup/12-install-vault.sh"
    echo ""
else
    log_error "$TESTS_FAILED of $TOTAL tests failed"
    echo ""
    log_info "Troubleshooting:"
    echo "  - Check MicroCeph status: sudo microceph status"
    echo "  - Check Ceph health: sudo microceph.ceph health detail"
    echo "  - Check rook-ceph pods: microk8s kubectl get pods -n rook-ceph"
    echo "  - Check CSI driver logs: microk8s kubectl logs -n rook-ceph -l app=csi-rbdplugin-provisioner"
    echo ""
    exit 1
fi
