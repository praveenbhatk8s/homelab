# ADR-006: Reading completeness as the primary service indicator

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

For a utility, the head-end being "up" matters less than whether every reading arrives. Concentrators buffer during outages, so a head-end can be down for an hour without data loss, while a misconfiguration that silently drops 2% of readings for a week costs real money in estimated bills and disputes.

## Decision

The primary service level indicator is **reading completeness**: readings stored for an interval divided by readings expected for that interval (meters registered × intervals), measured per interval once the reporting window has closed.

- SLO: 99.5% of expected readings stored within 2 hours of the interval end, over 30 days.
- Secondary SLIs: ingestion API availability, p99 ingestion latency, replication lag to DR.
- Alerts use multi-window burn rates against the completeness SLO, not raw error counts.

MeterFlow exposes what is needed to compute it across all replicas: `meterflow_readings_stored_total` (a counter per replica, summed in PromQL), `meterflow_registered_meters` and `meterflow_interval_seconds`. Expected readings per second are registered meters divided by the interval length.

## Alternatives considered

| Option | Why not chosen |
| --- | --- |
| HTTP availability only | Green dashboards while readings are lost to validation errors or a misrouted meter group. |
| Completeness measured in the billing system | Detects problems days later, after estimated bills are already produced. |

## Consequences

- The head-end must know how many meters should report, which requires the meter registry to be loaded and current.
- Lab 08 builds the recording rules and burn-rate alerts. Lab 02's MeterFlow already exposes the metrics, and lab 09 drill 6 shows the failure this SLI exists to catch.
