#!/usr/bin/env bash
# Platform layer: cert-manager, the customer CA issuer, namespaces with pod security, default-deny, RBAC.
source "$(dirname "$0")/lib.sh"
need kubectl helm

# Pin a version for anything beyond a lab, for example CERT_MANAGER_VERSION=v1.18.2.
# Check https://cert-manager.io/docs/releases/ for the current supported release.
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-}"
VERSION_FLAG=()
[[ -n "$CERT_MANAGER_VERSION" ]] && VERSION_FLAG=(--version "$CERT_MANAGER_VERSION")

info "installing cert-manager ${CERT_MANAGER_VERSION:-(latest)}"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update jetstack >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  "${VERSION_FLAG[@]}" \
  --set crds.enabled=true \
  --wait --timeout 5m >/dev/null

info "creating namespaces with restricted pod security"
kubectl apply -f "${LAB_DIR}/manifests/namespaces.yaml"

info "applying platform default-deny network policies"
kubectl apply -f "${LAB_DIR}/manifests/netpol-defaults.yaml"

info "creating the (simulated) customer corporate CA and its issuer"
kubectl apply -f "${LAB_DIR}/manifests/corporate-ca.yaml"
kubectl -n cert-manager wait --for=condition=Ready certificate/talheim-corporate-root --timeout=120s >/dev/null
kubectl wait --for=condition=Ready clusterissuer/talheim-corporate-ca --timeout=120s >/dev/null

info "binding customer groups to roles"
kubectl apply -f "${LAB_DIR}/manifests/rbac.yaml"

info "platform ready"
kubectl get clusterissuer
