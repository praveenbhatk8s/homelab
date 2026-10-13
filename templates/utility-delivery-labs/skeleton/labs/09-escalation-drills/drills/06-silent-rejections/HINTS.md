# Hints (read one at a time)

1. HTTP 200 means the batch was processed, not that every reading in it was stored. What does the head-end's response body contain?

2. Look at the head-end's metrics: `meterflow_readings_rejected_total` by reason, and its logs for "rejected".

3. Which meter IDs are rejected, and how does the head-end decide whether a meter exists? Compare `meterflow_registered_meters` with the number of meters the simulator runs.
