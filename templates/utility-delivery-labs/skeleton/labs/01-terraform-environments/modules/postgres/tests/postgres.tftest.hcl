mock_provider "azurerm" {}

variables {
  name_prefix         = "talheim-prod"
  location            = "germanywestcentral"
  resource_group_name = "rg-talheim-prod"
  sku_name            = "GP_Standard_D4ds_v5"
  storage_mb          = 1048576
  delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-talheim-prod/providers/Microsoft.Network/virtualNetworks/vnet-talheim-prod/subnets/snet-database"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-talheim-prod/providers/Microsoft.Network/privateDnsZones/talheim-prod.private.postgres.database.azure.com"
  tenant_id           = "00000000-0000-0000-0000-000000000001"

  entra_admin = {
    object_id      = "00000000-0000-0000-0000-000000000003"
    principal_name = "sg-talheim-dba"
    principal_type = "Group"
  }
}

run "server_has_no_public_access_and_no_password" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server.this.public_network_access_enabled == false
    error_message = "Public network access must be disabled."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.authentication[0].password_auth_enabled == false
    error_message = "Password authentication must be disabled; Entra ID only."
  }
}

run "tls_is_required" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server_configuration.require_tls.value == "on"
    error_message = "require_secure_transport must be on."
  }
}

run "no_ha_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_postgresql_flexible_server.this.high_availability) == 0
    error_message = "HA should be off unless asked for."
  }
}

run "ha_is_zone_redundant_when_enabled" {
  command = plan

  variables {
    high_availability = true
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.high_availability[0].mode == "ZoneRedundant"
    error_message = "HA must be zone-redundant."
  }
}

run "logical_replication_sets_wal_level" {
  command = plan

  variables {
    logical_replication = true
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_configuration.wal_level[0].value == "logical"
    error_message = "wal_level must be logical for the DR subscription."
  }
}

run "rejects_ha_on_burstable" {
  command = plan

  variables {
    sku_name          = "B_Standard_B2s"
    high_availability = true
  }

  expect_failures = [azurerm_postgresql_flexible_server.this]
}

run "rejects_retention_above_35_days" {
  command = plan

  variables {
    backup_retention_days = 40
  }

  expect_failures = [var.backup_retention_days]
}
