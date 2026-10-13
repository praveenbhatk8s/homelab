output "server_id" {
  description = "ID of the PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "fqdn" {
  description = "Private FQDN of the server."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "high_availability" {
  description = "True when zone-redundant HA is configured."
  value       = var.high_availability
}

output "backup_retention_days" {
  description = "Point-in-time restore window in days."
  value       = var.backup_retention_days
}
