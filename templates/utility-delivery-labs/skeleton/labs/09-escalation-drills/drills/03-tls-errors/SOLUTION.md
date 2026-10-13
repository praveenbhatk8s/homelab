# Solution: TLS errors since this morning

## Diagnosis

```bash
kubectl -n concentrators logs deploy/meter-sim --tail=5
# x509: certificate is valid for meterflow.talheim.example, not meterflow.meterflow.svc

kubectl -n meterflow get certificate meterflow -o jsonpath='{.spec.dnsNames}'
# ["meterflow.talheim.example"]

helm -n meterflow get manifest meterflow | grep -A6 'dnsNames:'
# the chart still lists the three service names

kubectl -n meterflow logs deploy/meterflow | grep "certificate loaded" | tail -2
# a new certificate was loaded with only the external name
```

## Root cause

Someone edited the Certificate by hand to add the external hostname, and replaced the list instead of adding to it. cert-manager reissued the certificate, the head-end reloaded it without a restart (as designed), and every client using the internal service name now fails hostname verification.

The automatic rotation that makes renewals painless also delivered the broken certificate within minutes. Good automation amplifies bad changes as fast as good ones.

## Fix

Restore the chart as the source of truth, and add the external name the right way:

```bash
helm -n meterflow upgrade meterflow ../02-hardened-platform/chart/meterflow --reuse-values \
  --set-json 'tls.extraDnsNames=["meterflow.talheim.example"]'
kubectl -n meterflow wait --for=condition=Ready certificate/meterflow --timeout=120s
```

Verify: the simulator's buffer drains, and `openssl s_client -verify_hostname meterflow.meterflow.svc` returns `Verify return code: 0 (ok)` through a port-forward.

## Prevention

- Resources owned by a chart are changed through the chart. GitOps (lab 04) would have reverted this edit automatically.
- Add a pipeline check that the Certificate always contains the service names clients use.
- Certificate changes are a change-managed item: they affect every client at once.

## Model narration

> TLS failures usually come down to three things: expired, untrusted issuer, or wrong name. The client error says the certificate is valid for the external hostname, not the service name, so it's the name.
>
> The Certificate resource only has the external name, but the chart has the service names. So someone edited the resource directly, probably while preparing the external hostname, and replaced the list instead of adding to it. Because the head-end reloads certificates automatically, the broken one was live within minutes.
>
> I'll put the chart back in charge and add the external name as a chart value, so both names are in the certificate. Once it's reissued, the concentrators reconnect and drain their buffers. The follow-up is GitOps, so a manual edit like this gets reverted rather than shipped.

## Customer update

> TLS is working again and buffered readings have been delivered. Cause: yesterday's preparation for the external hostname replaced the certificate's internal names instead of adding to them. Both names are now in the certificate, managed through our deployment code rather than by hand, so the change is reviewed in future.
