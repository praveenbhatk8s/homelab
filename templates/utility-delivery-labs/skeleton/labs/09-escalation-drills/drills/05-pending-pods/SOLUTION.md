# Solution: Scaled up, nothing changed

## Diagnosis

```bash
kubectl -n meterflow get pods
# three old pods Running; several new pods Pending

kubectl -n meterflow describe pod <pending-pod> | tail -5
# 0/4 nodes are available: 3 Insufficient cpu, 1 node(s) had untolerated taint ...

kubectl -n meterflow get deploy meterflow -o jsonpath='{.spec.template.spec.containers[0].resources}'
# requests.cpu: "32"
```

Each new pod requests 32 CPUs. No node has 32 CPUs free, so the scheduler can't place any of them. Because the CPU change is a template change, it also started a rolling update; with `maxUnavailable: 0` the old three keep running, so it looks like "nothing changed".

## Root cause

The vendor's sizing sheet gives 32 cores for a VM installation of the whole head-end. It was applied per pod. Requests reserve capacity whether it is used or not, and this service uses about 100m per pod in the lab.

## Fix

Choose requests from measured usage, not from guesses:

```bash
kubectl top pods -n meterflow        # needs metrics-server
```

Then scale out with realistic requests:

```bash
kubectl -n meterflow patch deployment meterflow --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"}]'
kubectl -n meterflow rollout status deploy/meterflow
```

And make the change in the chart values, not only in the cluster.

On AKS, the cluster autoscaler would have added nodes for the Pending pods, up to the node pool maximum. That hides the mistake and costs money: 6 pods × 32 CPUs = 192 reserved CPUs for a service that uses less than 1.

## Prevention

- Requests set from load-test measurements in staging, recorded in the chart with a comment.
- Alert on pods Pending for more than 5 minutes.
- A ResourceQuota per namespace, so an over-sized request fails fast with a clear message.

## Model narration

> The new pods are Pending, which means the scheduler can't place them. The event says insufficient CPU on every worker. Each pod now requests 32 CPUs, which is the vendor's sizing for a whole VM installation, and the service actually uses around a tenth of one CPU per pod.
>
> The old pods are untouched because the change also triggered a rolling update with max-unavailable zero, which is why it looked like nothing changed.
>
> I'll set requests from measured usage, scale to six, and put the values in the chart. On AKS this would have quietly added nodes instead, so it's worth adding a quota to catch over-sized requests before they cost money.

## Customer update

> Six replicas are now running for the load test. The vendor's sizing sheet describes a whole server, and it was applied to each pod, so the cluster couldn't place the new pods. We've set the reservation from measured usage, which also avoids paying for capacity that would sit idle.
