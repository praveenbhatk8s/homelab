# MeterFlow

A small head-end service for the labs. It receives batches of 15-minute meter readings over HTTPS, validates them, deduplicates them, and exposes the counters needed to measure reading completeness. `meter-sim` plays the concentrators, including buffering and replay when the head-end is down.

Standard library only, so it builds offline and the image stays tiny.

## Run locally

```bash
go test ./...
go run ./cmd/headend &                                  # plain HTTP on :8080, metrics on :9090
TARGET=http://localhost:8080/v1/readings INTERVAL=5s METERS=200 go run ./cmd/meter-sim
```

Use the same `INTERVAL` for both. Stop the head-end for a few intervals and restart it: the simulator's `meter_sim_buffered_readings` grows, then drains to zero once the head-end is back, and `meter_sim_readings_acked_total` catches up with `meter_sim_readings_generated_total`.

## API

`POST /v1/readings`

```json
{
  "concentrator": "C001",
  "readings": [
    {"meter_id": "M0000001", "interval_end": "2026-10-13T10:15:00Z", "kwh": 0.231}
  ]
}
```

The full contract is in [api/openapi.yaml](api/openapi.yaml).

Response: `{"accepted": 1, "duplicates": 0, "rejected": 0}`. Duplicates are accepted idempotently, so a concentrator can safely resend after a timeout.

Validation rejects unknown meters, interval ends not on a boundary, readings from the future, readings older than `MAX_AGE`, and implausible consumption values.

## Operations endpoints (port 9090)

| Path | Purpose |
| --- | --- |
| `/healthz` | Liveness: the process is running |
| `/readyz` | Readiness: returns 503 while draining after SIGTERM |
| `/metrics` | Prometheus metrics |

## Metrics

| Metric | Meaning |
| --- | --- |
| `meterflow_readings_received_total` | Readings received, valid or not |
| `meterflow_readings_stored_total` | Readings stored for the first time |
| `meterflow_readings_duplicate_total` | Readings already stored |
| `meterflow_readings_rejected_total{reason}` | Rejected readings by reason |
| `meterflow_batches_total{code}` | Batches by HTTP status |
| `meterflow_batch_duration_seconds` | Batch processing time (sum and count) |
| `meterflow_registered_meters` | Meters expected to report |
| `meterflow_interval_seconds` | Reading interval |
| `meterflow_tls_certificate_expiry_timestamp_seconds` | When the serving certificate expires |

Completeness across all replicas, in PromQL:

```promql
sum(rate(meterflow_readings_stored_total[30m]))
/
(max(meterflow_registered_meters) / max(meterflow_interval_seconds))
```

## Design notes

- **Graceful shutdown.** On SIGTERM the service fails readiness, keeps serving for `DRAIN_DELAY` while Kubernetes removes it from the Service endpoints, then finishes in-flight batches. No reading is lost during a rolling update.
- **Certificate rotation without restart.** The serving certificate is re-read when its file changes, so cert-manager can renew it in place.
- **Portable.** No writes to disk, unprivileged ports, any non-root UID. Runs under Kubernetes `restricted` Pod Security and OpenShift `restricted-v2`.
- **In-memory store.** Deduplication is per replica. Lab 06 moves storage to PostgreSQL with a unique key, which deduplicates across replicas.
