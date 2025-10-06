#!/bin/bash
set -e

echo "=== Cap-Admin Validation Test ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}✓ PASS: ${message}${NC}"
            ;;
        "FAIL")
            echo -e "${RED}✗ FAIL: ${message}${NC}"
            ;;
        "INFO")
            echo -e "${YELLOW}ℹ INFO: ${message}${NC}"
            ;;
    esac
}

# Test 1: Check if cap-admin DaemonSet is running
echo "Test 1: Checking cap-admin DaemonSet..."
if kubectl get daemonset cap-admin -n istio-system &>/dev/null; then
    print_status "PASS" "cap-admin DaemonSet exists"

    # Check if pods are running
    pod_count=$(kubectl get pods -n istio-system -l k8s-app=cap-admin --no-headers | wc -l)
    if [ $pod_count -gt 0 ]; then
        print_status "PASS" "cap-admin pods are running ($pod_count pods)"
    else
        print_status "FAIL" "No cap-admin pods found"
    fi
else
    print_status "FAIL" "cap-admin DaemonSet not found"
fi

# Test 2: Check if old istio-cni components are removed
echo -e "\nTest 2: Checking if old istio-cni components are removed..."
if kubectl get daemonset istio-cni-node -n kube-system &>/dev/null; then
    print_status "FAIL" "istio-cni-node DaemonSet still exists"
else
    print_status "PASS" "istio-cni-node DaemonSet has been removed"
fi

if kubectl get serviceaccount istio-cni -n kube-system &>/dev/null; then
    print_status "FAIL" "istio-cni ServiceAccount still exists"
else
    print_status "PASS" "istio-cni ServiceAccount has been removed"
fi

# Test 3: Check if cap-admin has NET_ADMIN capability
echo -e "\nTest 3: Checking cap-admin capabilities..."
if kubectl get daemonset cap-admin -n istio-system -o yaml | grep -q "NET_ADMIN"; then
    print_status "PASS" "cap-admin has NET_ADMIN capability"
else
    print_status "FAIL" "cap-admin does not have NET_ADMIN capability"
fi

if kubectl get daemonset cap-admin -n istio-system -o yaml | grep -q "NET_RAW"; then
    print_status "PASS" "cap-admin has NET_RAW capability"
else
    print_status "FAIL" "cap-admin does not have NET_RAW capability"
fi

# Test 4: Check istiod configuration
echo -e "\nTest 4: Checking istiod configuration..."
if kubectl get deployment istiod -n istio-system -o yaml | grep -q "ISTIO_CNI_ENABLED.*false"; then
    print_status "PASS" "istiod has ISTIO_CNI_ENABLED=false"
else
    print_status "FAIL" "istiod CNI configuration is incorrect"
fi

if kubectl get deployment istiod -n istio-system -o yaml | grep -q "ENABLE_NATIVE_SIDECARS.*true"; then
    print_status "PASS" "istiod has ENABLE_NATIVE_SIDECARS=true"
else
    print_status "FAIL" "istiod native sidecar configuration is incorrect"
fi

# Test 5: Deploy test application
echo -e "\nTest 5: Deploying test application..."
kubectl apply -f cap-admin-validation.yaml &>/dev/null
print_status "INFO" "Test application deployed"

# Wait for pods to be ready
echo "Waiting for test pod to be ready..."
if kubectl wait --for=condition=Ready pod/test-app -n cap-admin-test --timeout=60s &>/dev/null; then
    print_status "PASS" "Test pod is ready"

    # Check if sidecar is injected
    sidecar_count=$(kubectl get pod test-app -n cap-admin-test -o jsonpath='{.spec.containers[*].name}' | tr ' ' '\n' | grep istio-proxy | wc -l)
    if [ $sidecar_count -gt 0 ]; then
        print_status "PASS" "Istio sidecar has been injected"
    else
        print_status "FAIL" "Istio sidecar not injected"
    fi
else
    print_status "FAIL" "Test pod failed to become ready"
fi

# Test 6: Check iptables rules (if possible)
echo -e "\nTest 6: Checking traffic interception..."
test_pod_ip=$(kubectl get pod test-app -n cap-admin-test -o jsonpath='{.status.podIP}')
if [ -n "$test_pod_ip" ]; then
    print_status "INFO" "Test pod IP: $test_pod_ip"

    # Try to access the service
    echo "Testing service connectivity..."
    if kubectl exec -n cap-admin-test test-app -- wget -q --spider http://localhost/ &>/dev/null; then
        print_status "PASS" "Service connectivity test passed"
    else
        print_status "FAIL" "Service connectivity test failed"
    fi
else
    print_status "FAIL" "Could not get test pod IP"
fi

# Cleanup
echo -e "\nCleaning up test resources..."
kubectl delete -f cap-admin-validation.yaml &>/dev/null
kubectl delete namespace cap-admin-test &>/dev/null

echo -e "\n=== Cap-Admin Validation Complete ==="