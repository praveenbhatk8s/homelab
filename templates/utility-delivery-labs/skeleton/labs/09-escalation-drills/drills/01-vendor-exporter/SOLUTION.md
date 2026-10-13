# Solution: Vendor exporter never starts

## Diagnosis

```bash
kubectl -n meterflow get deploy legacy-exporter          # READY 0/1
kubectl -n meterflow get pods -l app=legacy-exporter     # nothing
kubectl -n meterflow describe rs -l app=legacy-exporter  # events at the bottom
```

The ReplicaSet events say the pod is forbidden because it violates PodSecurity "restricted": no `runAsNonRoot`, privilege escalation allowed, capabilities not dropped, no seccomp profile.

The pod was never created, so there are no pod events or logs. Operations "saw no errors" because the error lives on the ReplicaSet, one level down from where most people look.

## Root cause

The vendor's instructions use the standard `nginx` image, which runs as root and listens on port 80. The namespace enforces the restricted Pod Security Standard, so admission rejects the pod. On OpenShift this is the same failure as an image that needs `anyuid`.

## Fix

Don't relax the namespace. Run the exporter in a form that meets the contract:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-exporter
  namespace: meterflow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: legacy-exporter
  template:
    metadata:
      labels:
        app: legacy-exporter
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: exporter
          image: nginxinc/nginx-unprivileged:1.27   # runs as non-root on port 8080
          ports:
            - containerPort: 8080
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

For a real vendor product: ask the vendor for their non-root or OpenShift-certified image first. If none exists, rebuild it on a non-root base with group-0 permissions, and record the deviation.

The NetworkPolicy defaults will still block traffic to it until an allow rule is added, which is the next conversation with the customer.

## Prevention

- Add the workload contract (ADR-002) to the onboarding document given to vendors.
- Run `kubectl apply --dry-run=server` in CI for every third-party manifest, so admission errors appear in the pipeline, not in the cluster.

## Model narration (about 90 seconds)

> First, impact: this is the exporter only. Meter readings are unaffected, so it's medium priority, not an outage.
>
> A deployment with zero pods usually means the ReplicaSet couldn't create them, so I'll look there rather than for pod logs. The events say the pod violates the restricted pod security policy. The image is stock nginx, which runs as root on port 80, and this namespace only admits non-root pods.
>
> I won't relax the namespace, because that's the security baseline the customer approved, and it would also differ from how the DR site on OpenShift behaves. Instead I'll run the unprivileged build of the same image on port 8080, with the standard security context. That starts immediately.
>
> To stop this recurring, I'll add the workload contract to the vendor onboarding pack and add a server-side dry run to the pipeline.

## Customer update

> Hi Jonas, the exporter was blocked by the platform's security policy because the vendor's image runs as root. I've deployed the vendor's non-root version, which is running now. No impact on meter readings. One follow-up: it needs a network rule before Prometheus can scrape it; I'll send the change for approval today.
