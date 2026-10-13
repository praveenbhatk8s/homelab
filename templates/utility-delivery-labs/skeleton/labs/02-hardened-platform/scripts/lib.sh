# shellcheck shell=bash
# Shared helpers for the lab scripts. Source it; don't run it.

set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${LAB_DIR}/../.." && pwd)"

# kind (default), k3s, or existing (any cluster your kubeconfig points at).
CLUSTER_TYPE="${CLUSTER_TYPE:-kind}"
KIND_NAME="${KIND_NAME:-talheim}"
IMAGE="${IMAGE:-meterflow:0.1.0}"
# Compressed time for the lab: one "15-minute" interval every 10 seconds.
LAB_INTERVAL="${LAB_INTERVAL:-10s}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

need() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required tool: $cmd"
  done
}

# Start a port-forward in the background and wait until the local port answers.
# Usage: port_forward <namespace> <resource> <local:remote>
PF_PIDS=()
port_forward() {
  local ns="$1" res="$2" ports="$3" local_port="${3%%:*}"
  kubectl -n "$ns" port-forward "$res" "$ports" >/dev/null 2>&1 &
  PF_PIDS+=("$!")
  for _ in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${local_port}") 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  die "port-forward to ${ns}/${res} on ${local_port} did not come up"
}

stop_port_forwards() {
  for pid in "${PF_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  PF_PIDS=()
}

# Read one metric value (summed over label sets) from a Prometheus text endpoint.
# Usage: metric <url> <metric_name>
metric() {
  curl -fsS "$1" | awk -v m="$2" '$1 == m || index($1, m"{") == 1 { s += $2 } END { printf "%.0f\n", s }'
}
