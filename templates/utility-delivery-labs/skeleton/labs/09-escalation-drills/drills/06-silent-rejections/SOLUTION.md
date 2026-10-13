# Solution: Estimated readings, green dashboards

## Diagnosis

```bash
kubectl -n meterflow port-forward svc/meterflow 9090:9090 &
curl -s localhost:9090/metrics | grep -E 'rejected|registered'
# meterflow_readings_rejected_total{reason="unknown_meter"}  rising every interval
# meterflow_registered_meters 900

kubectl -n meterflow logs deploy/meterflow --tail=5
# "batch had rejected readings" ... rejected=10 total=100

kubectl -n concentrators port-forward deploy/meter-sim 9091:9091 &
curl -s localhost:9091/metrics | grep -E 'generated|acked|rejected'
# acked is about 90% of generated
```

The head-end knows 900 meters. The simulator, standing in for the field, has 1,000. Readings from meters 901 to 1,000 are rejected as unknown. Each batch still returns HTTP 200, because the batch was valid; the rejections are in the response body and in a metric nobody alerts on.

## Root cause

The meter registry wasn't updated when the new meters were activated. Every health signal the dashboards showed (pod status, HTTP codes, latency) was correct and irrelevant: the service was up and doing the wrong thing.

## Fix

```bash
helm -n meterflow upgrade meterflow ../02-hardened-platform/chart/meterflow --reuse-values \
  --set meterflow.meterCount=1000
```

Then recover the missing data. In this design, rejected readings are not retried by concentrators, because the head-end answered. In production that means asking the concentrator platform to resend the affected intervals, which is possible within the head-end's `MAX_AGE` window (48 hours), and telling billing which intervals to re-run.

## Prevention

- **Completeness is the SLI** (ADR-006): stored readings divided by expected readings. This incident drops it to 90% and pages within one burn-rate window, instead of billing noticing the next morning.
- Alert on any non-zero rate of `unknown_meter` rejections; it is never normal after rollout.
- Meter activation and registry update are one process, with a check that the counts match.

## Model narration

> The dashboards are green and billing says 10% is missing, so I trust billing: they're measuring the outcome, the dashboards are measuring the process.
>
> HTTP 200 only means the batch was accepted. Inside, the head-end is rejecting readings as unknown meters, about 10% of every batch. It thinks there are 900 meters; there are 1,000 since yesterday's activation.
>
> I'll update the registry so new readings are stored, then work with the concentrator team to resend the affected intervals while they're still inside the 48-hour window, and tell billing which intervals to re-run.
>
> The lesson is why our main SLO is reading completeness, not uptime. Completeness would have dropped to 90% this morning and paged us hours before billing noticed.

## Customer update

> Readings for the newly activated meters are now being stored. Cause: the head-end's meter registry wasn't updated with yesterday's activation, so their readings were rejected while the service itself stayed healthy. We're arranging a resend of the missed intervals, still within the 48-hour window, and will send billing the exact intervals to recalculate. We're adding an alert on reading completeness so a gap like this is caught within the hour.
