# Hints (read one at a time)

1. The head-end is healthy and receiving nothing. Look at the sender: `kubectl -n concentrators logs deploy/meter-sim --tail=20`. What kind of error is it: refused, timeout, TLS, or HTTP status?

2. A timeout to a healthy service inside the cluster usually means something is dropping packets. What drops packets between namespaces?

3. Compare `kubectl get ns concentrators --show-labels` with the `namespaceSelector` in `kubectl -n meterflow get networkpolicy meterflow -o yaml`.
