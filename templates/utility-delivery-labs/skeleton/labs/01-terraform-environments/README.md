# Lab 01: Terraform environments

Four Azure environments (dev, UAT, staging, prod) for Stadtwerke Talheim, built from one set of reusable modules. Every environment differs only through a profile table, every promise made to the customer is a test, and the tests run offline without an Azure account.

## What you'll practise

- Designing reusable modules with typed, validated inputs.
- Encoding customer requirements as guardrails: German regions only, no overlap with customer IP ranges, no public endpoints, no database passwords.
- Splitting environments into separate roots and state files (ADR-004).
- Testing Terraform with `terraform test` and mock providers.
- A plan-on-pull-request pipeline.
- Azure equivalents of the AWS services you already know.

## Layout

```
modules/
  network/          spoke VNet, standard /20 layout, NSGs, firewall route, hub peering, private DNS
  aks/              private AKS, Entra ID only, workload identity, Cilium network policy, 2 node pools
  postgres/         Flexible Server, private, Entra ID only, optional zone-redundant HA and logical replication
  monitoring/       Log Analytics workspace
  meter-platform/   composition: one customer environment, sized by profile
envs/
  dev/ uat/ staging/ prod/    one root and one state file each
```

## How environments differ

All differences are in `modules/meter-platform/main.tf`, in the `profiles` table. This is the table to show a customer who asks why UAT costs less than production.

| Setting | dev | uat | staging | prod |
| --- | --- | --- | --- | --- |
| Zones | 1 | 3 | 3 | 3 |
| AKS tier | Free | Standard | Standard | Standard |
| Workload nodes | D4s_v5, 1–3 | D4s_v5, 1–3 | D8s_v5, 3–9 | D8s_v5, 3–9 |
| PostgreSQL | Burstable B2s | GP D2ds_v5 | GP D4ds_v5 | GP D4ds_v5 |
| Database HA | No | No | Zone-redundant | Zone-redundant |
| Geo-redundant backup | No | No | No | Yes |
| Restore window | 7 days | 7 days | 7 days | 35 days |
| DR replication | No | No | Yes (rehearsals) | Yes |

Staging matches production's shape so load tests and upgrade rehearsals mean something. It is also the environment to schedule off when not in use.

## Run it

You need Terraform 1.9 or later (or OpenTofu 1.9+ with `TF=tofu`). No Azure account is needed for these steps.

```bash
cd labs/01-terraform-environments
make fmt-check     # formatting
make validate      # every module and environment
make test          # offline tests with mock providers
```

Expected: every test reports `pass`, including the ones that check bad input is rejected.

## The guardrails, and the test that proves each one

| Customer requirement | Guardrail | Test |
| --- | --- | --- |
| Data stays in Germany | `location` validation | `refuses_regions_outside_germany` |
| No clash with customer network | Overlap check on `address_space` | `rejects_a_spoke_that_overlaps_the_customer_network` |
| No public endpoints | Private AKS, no public PostgreSQL | `cluster_is_private_with_no_local_accounts`, `server_has_no_public_access_and_no_password` |
| Access only through customer identity | Local accounts off, Entra ID only on AKS and PostgreSQL | same tests |
| Database reachable only from AKS and ops | NSG rules on the database subnet | `postgres_is_only_reachable_from_aks_and_ops` |
| RPO 15 minutes via DR | `wal_level=logical` in staging and prod | `prod_replicates_to_dr` |
| Prod survives a zone failure | 3 zones, zone-redundant HA | `prod_is_zone_redundant_end_to_end` |
| Non-prod costs less | dev profile | `dev_is_cheap_and_says_so` |

## Exercises

Do them in order. Each one is a question you could be asked.

1. **Break a guardrail on purpose.** Change prod's `address_space` to `10.10.32.0/20` and run `make validate`. Read the error. Revert.
2. **Add a guardrail.** Add a validation to `meter-platform` that refuses `prod` unless `hub_vnet_id` and `firewall_private_ip` are both set, because production must not have direct internet egress. Write the test first, watch it fail, then make it pass.
3. **Refactor without destroying.** Rename `azurerm_subnet.internal_lb` to `azurerm_subnet.ingress` in the network module. Add a `moved` block so an existing environment would not destroy and recreate the subnet. Explain why this matters for a live customer.
4. **Add a Key Vault module** with RBAC authorisation, purge protection, a private endpoint in the `private_endpoints` subnet, and a test that public access is disabled. Check the current azurerm documentation for argument names first; some changed during the 4.x series.
5. **Triage the security scan.** Install Checkov and run `checkov -d modules --framework terraform`. For each finding, either fix it or write down why it does not apply. Then remove `--soft-fail` from the workflow.
6. **Cost it.** Use the Azure pricing calculator (or Infracost if you have it) to estimate dev and prod per month. Write both numbers in this README. Be ready to say which three lines dominate prod's cost.

## Optional: plan against Azure

Only if you have a subscription you can use. Planning costs nothing; applying does.

1. Create a storage account for state and copy `envs/dev/backend.hcl.example` to `backend.hcl`.
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in IDs from your tenant.
3. `cd envs/dev && terraform init -backend-config=backend.hcl && terraform plan`.
4. If you apply dev, destroy it the same day: `terraform destroy`. A private AKS cluster is only reachable from inside the VNet, so add a jump box or use `az aks command invoke` to test it.

For the pipeline's `plan` job, configure an Entra ID app with GitHub OIDC federation and set the repository variables named in `.github/workflows/lab01-terraform.yml`.

## AWS to Azure, for this lab

| What you know from AWS | What this lab uses |
| --- | --- |
| VPC, subnets, route tables | VNet, subnets, route table with a `VirtualAppliance` next hop |
| Security groups | NSGs (stateful, priority-ordered, apply to subnets) |
| Transit Gateway | Hub VNet with peering |
| RDS in private subnets | Flexible Server with a delegated subnet and private DNS zone |
| IAM database auth | Entra ID authentication on Flexible Server |
| EKS with IRSA | AKS with workload identity |
| EKS access entries | AKS with Entra ID and Azure RBAC, local accounts disabled |
| CloudWatch Container Insights | Log Analytics with the AKS monitoring add-on |
| S3 + DynamoDB state locking | Azure Storage blob with lease-based locking |

## Done when

- `make check` passes.
- Exercises 2 and 3 are done, with tests.
- You can explain the profile table and each guardrail aloud, using [TALK.md](TALK.md).
