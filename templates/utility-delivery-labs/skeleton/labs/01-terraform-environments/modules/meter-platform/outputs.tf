output "resource_group_name" {
  description = "Resource group of the environment."
  value       = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.cluster_name
}

output "postgres_fqdn" {
  description = "Private FQDN of the database."
  value       = module.postgres.fqdn
}

output "subnet_prefixes" {
  description = "Subnet prefixes, for the connectivity matrix."
  value       = module.network.subnet_prefixes
}

output "profile" {
  description = "The size and resilience profile this environment uses."
  value       = local.profile
}

output "resilience" {
  description = "Resilience summary, used by tests and the readiness checklist."
  value = {
    zones                 = module.aks.zones
    private_cluster       = module.aks.private_cluster
    database_ha           = module.postgres.high_availability
    backup_retention_days = module.postgres.backup_retention_days
    egress_via_firewall   = module.network.egress_via_firewall
  }
}
