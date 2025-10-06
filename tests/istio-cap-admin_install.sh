#!/bin/bash
set -e
echo "Installing Istio with cap-admin daemon (replacing Istio CNI)..."

# Install Istio CRDs first
cd common/istio
kustomize build istio-crds/base | kubectl apply -f -

# Install istio-system namespace
kustomize build istio-namespace/base | kubectl apply -f -

# Install Istio with cap-admin (instead of CNI)
echo "Installing Istio with cap-admin daemon..."
kustomize build istio-install/cap-admin | kubectl apply -f -

echo "Waiting for all Istio Pods to become ready..."
kubectl wait --for=condition=Ready pods --all -n istio-system --timeout 180s
kubectl wait --for=condition=Ready pods --all --all-namespaces --timeout 180s '--field-selector=status.phase!=Succeeded'

echo "Verifying cap-admin daemon is running..."
kubectl get pods -n istio-system -l k8s-app=cap-admin

echo "Istio with cap-admin installation completed successfully!"