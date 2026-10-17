#!/bin/bash
# Brings the homelab back after the Mac or OrbStack was stopped:
# starts OrbStack and the k3d cluster, unseals Vault, and re-syncs all secrets.
set -euo pipefail

CLUSTER="homelab"

echo "Starting OrbStack..."
open -a OrbStack
until docker --context orbstack info >/dev/null 2>&1; do sleep 2; done
docker context use orbstack >/dev/null

echo "Starting cluster '$CLUSTER'..."
k3d cluster start "$CLUSTER"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "Waiting for Vault..."
until kubectl -n vault get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; do sleep 2; done

if kubectl -n vault exec vault-0 -- vault status 2>/dev/null | grep -q 'Sealed *true'; then
  echo "Vault is sealed. Paste the unseal key:"
  kubectl -n vault exec -it vault-0 -- vault operator unseal
else
  echo "Vault is already unsealed."
fi
kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=60s

echo "Re-syncing secrets..."
kubectl annotate clustersecretstore vault force-sync="$(date +%s)" --overwrite >/dev/null
kubectl get externalsecret -A --no-headers | while read -r ns name _; do
  kubectl -n "$ns" annotate externalsecret "$name" force-sync="$(date +%s)" --overwrite >/dev/null
done
sleep 10
kubectl get externalsecret -A

echo "Homelab is up."
