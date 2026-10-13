# Solution: Release pipeline stuck

## Diagnosis

```bash
kubectl -n meterflow rollout status deploy/meterflow --timeout=5s
# Waiting for deployment "meterflow" rollout to finish: 1 out of 3 new replicas have been updated...

kubectl -n meterflow get pods
# three old pods Ready, one new pod Running but 0/1 Ready

kubectl -n meterflow describe pod <new-pod> | grep -A3 Readiness
# Readiness probe failed: ... connect: connection refused  (port 9999)

kubectl -n meterflow rollout history deploy/meterflow
```

The new revision's readiness probe points at port 9999, where nothing listens. The new pod never becomes Ready.

## Why production is fine

The rollout strategy is `maxUnavailable: 0, maxSurge: 1`. Kubernetes adds one new pod and only removes an old one once the new one is Ready. The new pod never is, so all three old pods keep serving. Production is entirely on the old version.

That setting turned a broken release into a stuck pipeline instead of an outage. With the default `maxUnavailable: 25%`, an old pod would have been removed straight away.

## Fix

```bash
kubectl -n meterflow rollout undo deploy/meterflow
kubectl -n meterflow rollout status deploy/meterflow
```

Then fix the probe in the release and re-run it in dev first.

## Prevention

- Render and lint the chart in CI; a test that the readiness probe port matches a declared container port.
- Progressive delivery with automated analysis (lab 04) would abort and roll back on its own.
- Pipeline timeout set to a few minutes, with a clear "rollout stalled" message, not 40.

## Model narration

> First, the release manager's questions. Production is on the old version, all three old pods are serving, and readings are fine. We should roll back the stuck release, but there's no outage to fix.
>
> The rollout added one new pod, which is running but never ready. Its readiness probe targets port 9999, and the app's health endpoint is on 9090. Because the deployment uses max-unavailable zero, Kubernetes won't remove an old pod until a new one is ready, which is exactly why there's no impact.
>
> I'll undo the rollout so the deployment is clean again, then fix the probe and push the release through dev before tonight's rehearsal.

## Customer update

> Production stayed on the previous version throughout; no impact on readings. The new release had a configuration error in its health check, so it never took traffic. We've rolled it back cleanly, fixed the check, and will re-run the release in dev before the 20:00 rehearsal.
