output "vnet_id" {
  description = "ID of the spoke VNet."
  value       = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  description = "Subnet IDs by role."
  value = {
    aks_nodes         = azurerm_subnet.aks_nodes.id
    database          = azurerm_subnet.database.id
    private_endpoints = azurerm_subnet.private_endpoints.id
    internal_lb       = azurerm_subnet.internal_lb.id
  }
}

output "subnet_prefixes" {
  description = "Subnet prefixes by role, for the connectivity matrix and NetworkPolicies."
  value       = local.subnet_prefixes
}

output "postgres_private_dns_zone_id" {
  description = "Private DNS zone for the PostgreSQL Flexible Server."
  value       = azurerm_private_dns_zone.postgres.id
}

output "egress_via_firewall" {
  description = "True when AKS egress is routed through the hub firewall."
  value       = var.firewall_private_ip != null
}
