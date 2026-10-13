#!/usr/bin/env bash
# Acceptance checks for the hardened platform. Prints a table and writes it to out/ as evidence
# for the handover pack (lab 10). Each check maps to a requirement or ADR in lab 00.
source "$(dirname "$0")/lib.sh"
need kubectl curl openssl awk

OUT_DIR="${LAB_DIR}/out"
mkdir -p "$OUT_DIR"
REPORT="${OUT_DIR}/acceptance-$(date +%Y%m%d-%H%M).md"
trap stop_port_forwards EXIT

RESULTS=()
FAILED=0
record() { # record <PASS|FAIL> <check> <requirement> <evidence>
  RESULTS+=("| $1 | $2 | $3 | $4 |")
  if [[ "$1" == "PASS" ]]; then
    printf '  \033[1;32mPASS\033[0m  %s\n' "$2"
  else
    printf '  \033[1;31mFAIL\033[0m  %s  (%s)\n' "$2" "$4"
    FAILED=$((FAILED + 1))
  fi
}

info "running acceptance checks against $(kubectl config current-context)"

# 1. Availability: all replicas ready.
want=$(kubectl -n meterflow get deploy meterflow -o jsonpath='{.spec.replicas}')
ready=$(kubectl -n meterflow get deploy meterflow -o jsonpath='{.status.readyReplicas}')
if [[ "${ready:-0}" == "$want" ]]; then
  record PASS "All head-end replicas ready" "HA" "${ready}/${want} ready"
else
  record FAIL "All head-end replicas ready" "HA" "${ready:-0}/${want} ready"
fi

# 2. Zone spread: replicas on more than one zone (or node, if zones aren't labelled).
zones=$(for n in $(kubectl -n meterflow get pods -l app.kubernetes.io/name=meterflow -o jsonpath='{.items[*].spec.nodeName}'); do
  kubectl get node "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}' 2>/dev/null || echo "$n"
done | sort -u | grep -c . || true)
if [[ "$zones" -ge 2 ]]; then
  record PASS "Replicas spread across zones" "Survive a zone failure" "${zones} zones in use"
else
  record FAIL "Replicas spread across zones" "Survive a zone failure" "${zones} zone in use"
fi

# 3. Container hardening as declared in the running pods.
sc=$(kubectl -n meterflow get pods -l app.kubernetes.io/name=meterflow -o jsonpath='{range .items[*]}{.spec.securityContext.runAsNonRoot}/{.spec.containers[0].securityContext.readOnlyRootFilesystem}/{.spec.containers[0].securityContext.allowPrivilegeEscalation}{"\n"}{end}' | sort -u)
if [[ "$sc" == "true/true/false" ]]; then
  record PASS "Non-root, read-only root FS, no privilege escalation" "ADR-002" "$sc"
else
  record FAIL "Non-root, read-only root FS, no privilege escalation" "ADR-002" "${sc//$'\n'/ }"
fi

# 4. Pod security admission rejects a root container.
if out=$(kubectl -n meterflow run psa-probe --image=busybox:1.36 --restart=Never --dry-run=server -- sleep 1 2>&1); then
  record FAIL "Restricted pod security rejects a root pod" "ADR-002" "root pod was admitted"
else
  if grep -q "violates PodSecurity" <<<"$out"; then
    record PASS "Restricted pod security rejects a root pod" "ADR-002" "rejected: violates PodSecurity restricted"
  else
    record FAIL "Restricted pod security rejects a root pod" "ADR-002" "rejected for another reason: ${out:0:80}"
  fi
fi

# 5. OpenShift parity: the image runs with an arbitrary high UID, as restricted-v2 would assign.
kubectl -n meterflow delete pod uid-probe --ignore-not-found --wait=true >/dev/null
kubectl -n meterflow run uid-probe --image="$IMAGE" --restart=Never --labels=probe=uid \
  --env=INTERVAL=10s --env=DRAIN_DELAY=0s \
  --overrides='{"spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":1000680000,"runAsGroup":0,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"uid-probe","image":"'"$IMAGE"'","imagePullPolicy":"IfNotPresent","securityContext":{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}]}}' >/dev/null
if kubectl -n meterflow wait --for=condition=Ready pod/uid-probe --timeout=60s >/dev/null 2>&1; then
  record PASS "Image runs as an arbitrary UID" "ADR-002, OpenShift DR" "UID 1000680000, group 0"
else
  record FAIL "Image runs as an arbitrary UID" "ADR-002, OpenShift DR" "pod not ready; see kubectl -n meterflow logs uid-probe"
fi
kubectl -n meterflow delete pod uid-probe --wait=false >/dev/null 2>&1 || true

# 6. Network policy: an unlabelled namespace cannot reach the head-end.
# A plain-HTTP request to the TLS port gets an immediate 400 if the connection is allowed, and a
# timeout if NetworkPolicy drops it. Only a timeout counts as a pass, so an image-pull or DNS error
# can't be mistaken for a working policy.
kubectl create namespace netpol-probe --dry-run=client -o yaml | kubectl apply -f - >/dev/null
probe_out=$(kubectl -n netpol-probe run probe --image=busybox:1.36 --restart=Never --rm -i --quiet \
  --command -- wget -T 4 -O /dev/null http://meterflow.meterflow.svc:8080/ 2>&1 || true)
if grep -qi "timed out" <<<"$probe_out"; then
  record PASS "Unauthorised namespace cannot reach the head-end" "Default deny, connectivity matrix" "connection timed out"
else
  record FAIL "Unauthorised namespace cannot reach the head-end" "Default deny, connectivity matrix" "$(tr '\n' ' ' <<<"${probe_out:0:100}")"
fi
kubectl delete namespace netpol-probe --wait=false >/dev/null

# 7. TLS: the head-end's certificate verifies against the customer CA for its service name.
kubectl -n meterflow get secret meterflow-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "${OUT_DIR}/.ca.crt"
port_forward meterflow svc/meterflow 18443:8080
tls_out=$(openssl s_client -connect 127.0.0.1:18443 -servername meterflow.meterflow.svc \
  -verify_hostname meterflow.meterflow.svc -CAfile "${OUT_DIR}/.ca.crt" </dev/null 2>/dev/null || true)
if grep -q "Verify return code: 0 (ok)" <<<"$tls_out"; then
  issuer=$(grep -m1 "^issuer=" <<<"$tls_out" | sed 's/^issuer=//')
  record PASS "TLS chains to the customer CA" "Customer requirement 6" "${issuer:-verified}"
else
  record FAIL "TLS chains to the customer CA" "Customer requirement 6" "$(grep -m1 'Verify return code' <<<"$tls_out" || echo 'no TLS handshake')"
fi
rm -f "${OUT_DIR}/.ca.crt"

# 8. Certificate lifetime: more than 30 days left.
expiry=$(kubectl -n meterflow get certificate meterflow -o jsonpath='{.status.notAfter}')
if [[ -n "$expiry" ]]; then
  exp_s=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry" +%s)
  days=$(( (exp_s - $(date +%s)) / 86400 ))
  if [[ "$days" -gt 30 ]]; then
    record PASS "Certificate valid for more than 30 days" "Operability" "${days} days left, renews 30 days before expiry"
  else
    record FAIL "Certificate valid for more than 30 days" "Operability" "${days} days left"
  fi
else
  record FAIL "Certificate valid for more than 30 days" "Operability" "certificate has no notAfter"
fi

# 9. Reading completeness: everything the meters produced was acknowledged and nothing rejected.
port_forward concentrators deploy/meter-sim 19091:9091
generated=0; acked=0; buffered=0
for _ in $(seq 1 18); do
  generated=$(metric http://127.0.0.1:19091/metrics meter_sim_readings_generated_total)
  acked=$(metric http://127.0.0.1:19091/metrics meter_sim_readings_acked_total)
  buffered=$(metric http://127.0.0.1:19091/metrics meter_sim_buffered_readings)
  [[ "$generated" -gt 0 && "$buffered" -eq 0 ]] && break
  sleep 5
done
rejected=$(metric http://127.0.0.1:19091/metrics meter_sim_readings_rejected_total)
if [[ "$generated" -gt 0 ]]; then
  ratio=$(awk -v a="$acked" -v g="$generated" 'BEGIN { printf "%.4f", a / g }')
  if awk -v r="$ratio" 'BEGIN { exit !(r >= 0.995) }' && [[ "$rejected" -eq 0 ]]; then
    record PASS "Reading completeness at least 99.5%" "ADR-006 SLO" "${acked}/${generated} acknowledged (${ratio}), ${rejected} rejected"
  else
    record FAIL "Reading completeness at least 99.5%" "ADR-006 SLO" "${acked}/${generated} acknowledged (${ratio}), ${rejected} rejected, ${buffered} buffered"
  fi
else
  record FAIL "Reading completeness at least 99.5%" "ADR-006 SLO" "no readings generated yet; wait a few intervals"
fi
stop_port_forwards

# 10. RBAC matrix for the customer's groups.
can() { kubectl auth can-i "$@" -n meterflow 2>/dev/null || true; }
rbac_ok=true
rbac_detail=()
check_rbac() { # check_rbac <expected yes|no> <group> <verb> <resource...>
  local expected="$1" group="$2"; shift 2
  local got
  got=$(can "$@" --as="lab-user" --as-group="$group")
  rbac_detail+=("${group#talheim:} $* = ${got}")
  [[ "$got" == "$expected" ]] || rbac_ok=false
}
check_rbac yes talheim:operations get pods/log
check_rbac yes talheim:operations patch deployments
check_rbac no  talheim:operations get secrets
check_rbac no  talheim:operations delete deployments
check_rbac yes talheim:delivery   create deployments
check_rbac no  talheim:auditors   get secrets
check_rbac yes talheim:auditors   list pods
if $rbac_ok; then
  record PASS "Customer groups have exactly the intended access" "Least privilege" "7 of 7 checks as expected"
else
  record FAIL "Customer groups have exactly the intended access" "Least privilege" "$(IFS='; '; echo "${rbac_detail[*]}")"
fi

# Report
{
  echo "# Acceptance evidence: MeterFlow hardened platform"
  echo
  echo "- Cluster context: \`$(kubectl config current-context)\`"
  echo "- Kubernetes server version: $(kubectl get --raw /version 2>/dev/null | awk -F'"' '/gitVersion/ {print $4; exit}' || echo unknown)"
  echo "- Image: \`${IMAGE}\`"
  echo "- Run at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "| Result | Check | Requirement | Evidence |"
  echo "| --- | --- | --- | --- |"
  printf '%s\n' "${RESULTS[@]}"
} > "$REPORT"

echo
info "report written to ${REPORT#"${REPO_DIR}"/}"
if [[ "$FAILED" -gt 0 ]]; then
  die "${FAILED} check(s) failed"
fi
info "all checks passed"
