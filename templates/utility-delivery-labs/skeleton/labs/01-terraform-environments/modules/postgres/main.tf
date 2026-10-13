# PostgreSQL Flexible Server for meter readings.

resource "azurerm_postgresql_flexible_server" "this" {
  name                = "psql-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = var.postgres_version
  sku_name            = var.sku_name
  storage_mb          = var.storage_mb
  auto_grow_enabled   = true
  zone                = var.primary_zone

  # ADR-005: reachable only inside the VNet.
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup

  # Entra ID only. No database password exists, so none can leak into state, CI logs or a wiki.
  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }

  dynamic "high_availability" {
    for_each = var.high_availability ? [1] : []

    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = var.standby_zone
    }
  }

  tags = var.tags

  lifecycle {
    # After an HA failover, Azure swaps the primary and standby zones. Without this, the next
    # plan would try to move them back, which forces another failover.
    ignore_changes = [zone, high_availability[0].standby_availability_zone]

    precondition {
      condition     = !var.high_availability || !startswith(var.sku_name, "B_")
      error_message = "High availability is not supported on Burstable (B_) SKUs. Use a General Purpose SKU."
    }

    precondition {
      condition     = !var.high_availability || var.primary_zone != var.standby_zone
      error_message = "The HA standby must be in a different zone from the primary."
    }
  }
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  object_id           = var.entra_admin.object_id
  principal_name      = var.entra_admin.principal_name
  principal_type      = var.entra_admin.principal_type
}

# ADR-003: logical replication to the DR site needs wal_level=logical. Changing it restarts the server.
resource "azurerm_postgresql_flexible_server_configuration" "wal_level" {
  count = var.logical_replication ? 1 : 0

  name      = "wal_level"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "logical"
}

resource "azurerm_postgresql_flexible_server_configuration" "require_tls" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "on"
}
