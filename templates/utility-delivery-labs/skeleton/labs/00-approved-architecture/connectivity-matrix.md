# Connectivity matrix

The customer's network and security teams approve flows, not architectures. Send them this table early, in the format they ask for, and keep it current. Every row here also exists as a NetworkPolicy or firewall rule in the labs.

All flows are TCP unless noted. "Prod" ranges shown; other environments follow the same pattern in their own spoke.

## Meter and integration traffic

| # | Source | Destination | Port | Protocol | Purpose | Owner of the rule |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Concentrators 100.64.0.0/16 | Prod internal LB 10.44.6.10 | 8443 | HTTPS (mTLS) | Meter readings to head-end | Customer firewall + Azure Firewall |
| 2 | Concentrators 100.64.0.0/16 | DR head-end VIP 10.10.20.50 | 8443 | HTTPS (mTLS) | Meter readings during DR | Customer firewall (disabled until failover) |
| 3 | Billing system 10.10.30.0/24 | Prod internal LB 10.44.6.11 | 443 | HTTPS | Readings API | Customer firewall + Azure Firewall |
| 4 | Prod PostgreSQL 10.44.4.0/24 | DR PostgreSQL 10.10.20.60 | 5432 | PostgreSQL over TLS | Logical replication | Azure Firewall + customer firewall |

## Operations access

| # | Source | Destination | Port | Protocol | Purpose | Owner of the rule |
| --- | --- | --- | --- | --- | --- | --- |
| 5 | Operations jump hosts 10.10.5.0/24 | AKS private API endpoint | 443 | HTTPS | kubectl through Entra ID | Customer firewall + Azure Firewall |
| 6 | Operations jump hosts 10.10.5.0/24 | Prod PostgreSQL 10.44.4.0/24 | 5432 | PostgreSQL over TLS | DBA access, Entra ID auth | Customer firewall + Azure Firewall |
| 7 | Private CI runners 10.10.6.0/24 | AKS private API endpoint | 443 | HTTPS | Pipeline deploys and checks | Customer firewall + Azure Firewall |

## DNS

| # | Source | Destination | Port | Protocol | Purpose |
| --- | --- | --- | --- | --- | --- |
| 8 | Customer DNS servers 10.10.1.10–11 | Azure DNS Private Resolver inbound 10.40.0.68 | 53 | UDP and TCP | Resolve Azure private zones from on-prem |
| 9 | Azure DNS Private Resolver outbound 10.40.0.84 | Customer DNS servers 10.10.1.10–11 | 53 | UDP and TCP | Resolve `stadtwerke-talheim.internal` from Azure |

## Egress from Azure to the internet (through Azure Firewall)

| # | Destination FQDN | Port | Purpose |
| --- | --- | --- | --- |
| 10 | `mcr.microsoft.com`, `*.data.mcr.microsoft.com` | 443 | AKS system images |
| 11 | `management.azure.com`, `login.microsoftonline.com` | 443 | AKS control and Entra ID |
| 12 | `packages.aks.azure.com`, `acs-mirror.azureedge.net` | 443 | Node image and binary downloads |
| 13 | `*.azurecr.io` (the customer's registry, private endpoint preferred) | 443 | Application images |

Rows 10 to 12 are illustrative. The authoritative list of required AKS egress endpoints changes; take it from Microsoft's current AKS outbound-rules documentation at build time and record the date you took it.

## Inside the cluster (NetworkPolicy)

| # | From | To | Port | Purpose |
| --- | --- | --- | --- | --- |
| 14 | Gateway namespace | `meterflow` pods | 8080 | Ingress to the head-end |
| 15 | `meterflow` pods | PostgreSQL (database subnet) | 5432 | Store readings |
| 16 | `monitoring` namespace | `meterflow` pods | 9090 | Metrics scrape |
| 17 | All pods | `kube-system` CoreDNS | 53 UDP and TCP | Name resolution |

Everything not listed is denied. Lab 02 implements rows 14, 16 and 17 against a local cluster, and lab 09 drill 2 breaks one of them on purpose.

## How to use this in the interview

When asked how you work with customer network teams: "I send a connectivity matrix in week one, in their format, with an owner per rule. Firewall changes are the most common reason a go-live slips, and a complete list up front turns a month of back-and-forth into one review."
