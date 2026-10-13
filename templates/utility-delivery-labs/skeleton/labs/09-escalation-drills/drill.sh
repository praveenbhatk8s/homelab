#!/usr/bin/env bash
# Inject one fault into the lab 02 platform, as if a customer escalation had just arrived.
#
#   ./drill.sh start <1-6>   inject a fault (read the matching TICKET.md, not the script)
#   ./drill.sh reset         put everything back the way lab 02 left it
#   ./drill.sh list          show the drills by title only
#
# Don't read the cases below before doing the drill: the point is to diagnose from symptoms.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART="${LAB_DIR}/../02-hardened-platform/chart/meterflow"

titles=(
  ""
  "Vendor exporter never starts"
  "Readings stopped arriving"
  "TLS errors since this morning"
  "Release pipeline stuck for 40 minutes"
  "Scaled up for the load test, but nothing changed"
  "Billing sees estimated readings, dashboards are green"
)

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

start() {
  case "$1" in
    1)
      kubectl -n meterflow create deployment legacy-exporter --image=nginx:1.27 --port=80 >/dev/null
      ;;
    2)
      kubectl label namespace concentrators meterflow.io/role- >/dev/null
      ;;
    3)
      kubectl -n meterflow patch certificate meterflow --type=json \
        -p='[{"op":"replace","path":"/spec/dnsNames","value":["meterflow.talheim.example"]}]' >/dev/null
      ;;
    4)
      kubectl -n meterflow patch deployment meterflow --type=json \
        -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":9999},
             {"op":"add","path":"/spec/template/metadata/annotations","value":{"release":"2026.10.2"}}]' >/dev/null
      ;;
    5)
      kubectl -n meterflow patch deployment meterflow --type=json \
        -p='[{"op":"replace","path":"/spec/replicas","value":6},
             {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"32"}]' >/dev/null
      ;;
    6)
      kubectl -n meterflow set env deployment/meterflow METER_COUNT=900 >/dev/null
      ;;
    *)
      usage
      ;;
  esac
  printf 'Drill %s started: "%s"\nOpen drills/0%s-*/TICKET.md and work it like a real escalation.\n' "$1" "${titles[$1]}" "$1"
}

reset() {
  kubectl -n meterflow delete deployment legacy-exporter --ignore-not-found >/dev/null
  kubectl label namespace concentrators meterflow.io/role=concentrator --overwrite >/dev/null

  # Undo each drill's drift explicitly, then let Helm reconcile anything else back to the chart.
  kubectl -n meterflow patch certificate meterflow --type=json \
    -p='[{"op":"replace","path":"/spec/dnsNames","value":["meterflow","meterflow.meterflow.svc","meterflow.meterflow.svc.cluster.local"]}]' >/dev/null 2>&1 || true
  kubectl -n meterflow patch deployment meterflow --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":"metrics"},
         {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"100m"},
         {"op":"replace","path":"/spec/replicas","value":3}]' >/dev/null 2>&1 || true
  kubectl -n meterflow set env deployment/meterflow METER_COUNT=1000 >/dev/null

  # The chart is the source of truth: a Helm upgrade with the same values reconciles remaining drift.
  helm -n meterflow upgrade meterflow "$CHART" --reuse-values --wait --timeout 5m >/dev/null
  kubectl -n meterflow rollout status deployment/meterflow --timeout=180s >/dev/null
  echo "Reset complete. Give the simulator two intervals to drain its buffer."
}

case "${1:-}" in
  start) [[ $# -eq 2 ]] || usage; start "$2" ;;
  reset) reset ;;
  list)  for i in 1 2 3 4 5 6; do printf '%s. %s\n' "$i" "${titles[$i]}"; done ;;
  *)     usage ;;
esac
