# Hints (read one at a time)

1. `kubectl -n meterflow get pods` and `kubectl -n meterflow rollout status deploy/meterflow`. How many pods are old, how many new, and which are Ready?

2. A new pod that is Running but never Ready: describe it and read the probe failures.

3. Why are readings still arriving? Look at the deployment's `strategy` section.
