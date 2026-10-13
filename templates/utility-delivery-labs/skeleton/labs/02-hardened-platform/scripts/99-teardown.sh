#!/usr/bin/env bash
# Remove the lab. For kind, deletes the whole cluster; otherwise removes only what the lab created.
source "$(dirname "$0")/lib.sh"

if [[ "$CLUSTER_TYPE" == "kind" ]]; then
  info "deleting kind cluster '$KIND_NAME'"
  kind delete cluster --name "$KIND_NAME"
  exit 0
fi

info "removing lab resources from $(kubectl config current-context)"
helm uninstall meterflow -n meterflow 2>/dev/null || true
kubectl delete -f "${LAB_DIR}/manifests/simulator.yaml" --ignore-not-found
kubectl delete -f "${LAB_DIR}/manifests/rbac.yaml" --ignore-not-found
kubectl delete -f "${LAB_DIR}/manifests/corporate-ca.yaml" --ignore-not-found
kubectl delete -f "${LAB_DIR}/manifests/netpol-defaults.yaml" --ignore-not-found
kubectl delete -f "${LAB_DIR}/manifests/namespaces.yaml" --ignore-not-found
info "cert-manager left installed; remove it with: helm uninstall cert-manager -n cert-manager"
