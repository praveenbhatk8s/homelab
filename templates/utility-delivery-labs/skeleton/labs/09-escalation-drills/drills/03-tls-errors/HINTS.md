# Hints (read one at a time)

1. The three usual suspects: expired, untrusted issuer, wrong name. The client's error message says which. Read it exactly: `kubectl -n concentrators logs deploy/meter-sim --tail=5`.

2. Look at what's in the certificate the server presents now: `kubectl -n meterflow get certificate meterflow -o yaml`, or port-forward and use `openssl s_client`.

3. Who changed the Certificate resource, and is that change in the chart? Compare it with `helm -n meterflow get manifest meterflow`.
