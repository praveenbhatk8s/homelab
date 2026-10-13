#!/usr/bin/env bash
# Build MeterFlow, load the image, deploy the chart, and start the simulated concentrators.
source "$(dirname "$0")/lib.sh"
need kubectl helm docker

info "building ${IMAGE}"
docker build -t "$IMAGE" "${REPO_DIR}/apps/meterflow"

case "$CLUSTER_TYPE" in
  kind)
    info "loading image into kind"
    kind load docker-image "$IMAGE" --name "$KIND_NAME"
    ;;
  k3s)
    info "importing image into k3s containerd (needs sudo on the k3s host)"
    docker save "$IMAGE" | sudo k3s ctr images import -
    ;;
  existing)
    warn "CLUSTER_TYPE=existing: push ${IMAGE} to a registry your cluster can pull from,"
    warn "then rerun with IMAGE=<registry>/meterflow:0.1.0"
    ;;
esac

REPO="${IMAGE%:*}"
TAG="${IMAGE##*:}"

info "deploying the meterflow chart (interval ${LAB_INTERVAL})"
helm upgrade --install meterflow "${LAB_DIR}/chart/meterflow" \
  --namespace meterflow \
  --set image.repository="$REPO" \
  --set image.tag="$TAG" \
  --set meterflow.interval="$LAB_INTERVAL" \
  --wait --timeout 5m

kubectl -n meterflow wait --for=condition=Ready certificate/meterflow --timeout=120s >/dev/null

# Concentrators trust the customer CA. In production the customer distributes this bundle
# (or trust-manager does); here we copy it from the issued certificate.
info "publishing the CA bundle to the concentrators namespace"
kubectl -n meterflow get secret meterflow-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "${LAB_DIR}/.ca.crt"
kubectl -n concentrators create configmap talheim-ca --from-file=ca.crt="${LAB_DIR}/.ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
rm -f "${LAB_DIR}/.ca.crt"

info "starting simulated concentrators"
sed -e "s|image: meterflow:0.1.0|image: ${IMAGE}|" -e "s|value: 10s|value: ${LAB_INTERVAL}|" \
  "${LAB_DIR}/manifests/simulator.yaml" | kubectl apply -f -
kubectl -n concentrators rollout status deployment/meter-sim --timeout=120s

info "deployed. Wait about three intervals, then run scripts/03-acceptance.sh"
kubectl -n meterflow get pods -o wide
