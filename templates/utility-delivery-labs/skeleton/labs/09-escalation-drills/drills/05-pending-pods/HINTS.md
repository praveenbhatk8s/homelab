# Hints (read one at a time)

1. `kubectl -n meterflow get pods`. What status are the new pods in?

2. Describe one of the Pending pods and read the scheduler's message.

3. Compare what each pod requests with what the nodes can offer: `kubectl describe nodes | grep -A6 'Allocatable'` and `kubectl -n meterflow get deploy meterflow -o jsonpath='{.spec.template.spec.containers[0].resources}'`.
