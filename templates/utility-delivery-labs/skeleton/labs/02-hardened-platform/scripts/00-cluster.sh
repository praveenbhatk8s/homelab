#!/usr/bin/env bash
# Create (or check) the cluster, label zones, and prove NetworkPolicy is enforced.
source "$(dirname "$0")/lib.sh"
need kubectl

case "$CLUSTER_TYPE" in
  kind)
    need kind docker
    if kind get clusters 2>/dev/null | grep -qx "$KIND_NAME"; then
      info "kind cluster '$KIND_NAME' already exists"
    else
      info "creating kind cluster '$KIND_NAME' (1 control plane, 3 workers)"
      kind create cluster --config "${LAB_DIR}/kind.yaml" --name "$KIND_NAME"
    fi
    kubectl config use-context "kind-${KIND_NAME}" >/dev/null

    info "labelling workers as zones 1-3"
    i=1
    for node in $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name); do
      kubectl label "$node" "topology.kubernetes.io/zone=zone-${i}" --overwrite >/dev/null
      i=$((i + 1))
    done
    ;;
  k3s|existing)
    info "using the current kubeconfig context: $(kubectl config current-context)"
    if ! kubectl get nodes -o jsonpath='{.items[*].metadata.labels}' | grep -q 'topology.kubernetes.io/zone'; then
      warn "no zone labels found. Topology spread still works per node. To simulate zones:"
      warn "  kubectl label node <name> topology.kubernetes.io/zone=zone-1"
    fi
    ;;
  *)
    die "CLUSTER_TYPE must be kind, k3s or existing"
    ;;
esac

kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
kubectl get nodes -L topology.kubernetes.io/zone

# Default-deny policies are only as good as the CNI enforcing them. Check before relying on them.
info "checking that the CNI enforces NetworkPolicy"
kubectl create namespace np-check --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n np-check run server --image=busybox:1.36 --restart=Never --labels=app=server \
  --command -- httpd -f -p 8080 >/dev/null 2>&1 || true
kubectl -n np-check wait --for=condition=Ready pod/server --timeout=120s >/dev/null
SERVER_IP="$(kubectl -n np-check get pod server -o jsonpath='{.status.podIP}')"

cat <<'EOF' | kubectl apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-ingress
  namespace: np-check
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes: ["Ingress"]
EOF
sleep 5

# Only a timeout proves the policy dropped the traffic; any other error (image pull, DNS) is inconclusive.
client_out=$(kubectl -n np-check run client --image=busybox:1.36 --restart=Never --rm -i --quiet \
  --command -- wget -T 3 -O /dev/null "http://${SERVER_IP}:8080/" 2>&1 || true)
if grep -qi "timed out" <<<"$client_out"; then
  ENFORCED=yes
else
  ENFORCED=no
fi
kubectl delete namespace np-check --wait=false >/dev/null

if [[ "$ENFORCED" == "yes" ]]; then
  info "NetworkPolicy is enforced"
else
  warn "NetworkPolicy is NOT enforced by this cluster's CNI. The default-deny rules in this lab would"
  warn "be silently ignored. Use a recent kind release (its kindnet enforces NetworkPolicy), k3s (built-in),"
  warn "or install Calico or Cilium, then run this script again."
  exit 1
fi
