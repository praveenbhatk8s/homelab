# Solution: Readings stopped arriving

## Diagnosis

```bash
kubectl -n meterflow get pods                               # all Ready
kubectl -n concentrators logs deploy/meter-sim --tail=20    # "head-end unreachable ... context deadline exceeded"
kubectl -n concentrators port-forward deploy/meter-sim 9091:9091 &
curl -s localhost:9091/metrics | grep -E 'buffered|post_errors'   # buffer growing every interval
kubectl get ns concentrators --show-labels                  # meterflow.io/role label is gone
kubectl -n meterflow get networkpolicy meterflow -o jsonpath='{.spec.ingress[0]}'
```

Timeouts, not refusals or TLS errors, point at the network. The head-end's NetworkPolicy admits traffic only from namespaces labelled `meterflow.io/role: concentrator`. The "label tidy-up" removed that label, so every connection is silently dropped.

## Root cause

Trust between namespaces is based on a label, and the label was changed by hand outside the change process. The policy did exactly what it was told.

## Stabilise and fix

```bash
kubectl label namespace concentrators meterflow.io/role=concentrator
```

Verify with the same signal that showed the problem: `meter_sim_buffered_readings` drops to zero within one or two intervals, and `meter_sim_readings_acked_total` catches up with `generated`. Then confirm no readings were lost: `meter_sim_readings_lost_total` is still zero.

## How long did we have?

Buffer limit per concentrator divided by readings per interval per concentrator. In the lab: 200,000 ÷ 100 = 2,000 intervals. In the real design, ask the customer: the four-hour RTO depends on this number (lab 00, open questions).

## Prevention

- Namespaces and their labels are managed by GitOps, so a manual change is reverted and shows up in review.
- Restrict who may change namespace labels (RBAC on `namespaces` patch), because labels are a security control here.
- Alert on `meter_sim_buffered_readings` (in production: completeness dropping for the newest interval) within two intervals, not when the control room notices.

## Model narration

> Impact first: no readings for a few intervals, but concentrators buffer, so we have time. I want to know roughly how much, so I'll check the buffer size while I work.
>
> The head-end is healthy, so I'll look at the sender. The simulator logs show timeouts. A timeout to a healthy in-cluster service usually means packets are being dropped rather than rejected, and inside a cluster that's usually a NetworkPolicy.
>
> The head-end's policy admits only namespaces with the concentrator role label. The concentrators namespace doesn't have it any more, which matches the "label tidy-up" in the ticket. Restoring the label is safe and immediate, so I'll do that first.
>
> The buffer is draining and acknowledged readings are catching up, with nothing lost. The real fix is process: namespace labels are a security control, so they should be in Git and changes should go through review.

## Customer update

> Readings are flowing again and the backlog has been delivered; no readings were lost. Cause: a namespace label used by the security rules was removed during this afternoon's tidy-up, which blocked the concentrators. We've restored it and will move these labels under change control so it can't happen silently again.
