# Ticket: Scaled up for the load test, but nothing changed

**From:** Performance test lead
**Priority:** Medium
**Received:** 10:30

> We scaled the head-end to 6 replicas and gave it more CPU for this afternoon's load test, using the CPU figure from the vendor's sizing sheet. Still only 3 pods are serving. The test starts at 14:00. What's wrong?

---

Before running anything: what are the first three reasons a pod doesn't start after a scale-up?
