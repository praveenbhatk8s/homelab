# Hints (read one at a time)

1. A Deployment with no pods means the ReplicaSet couldn't create them. Where would the ReplicaSet record why?

2. `kubectl -n meterflow describe rs -l app=legacy-exporter`. Read the events at the bottom.

3. The namespace has a label that starts with `pod-security.kubernetes.io`. What does the image need that the namespace forbids?
