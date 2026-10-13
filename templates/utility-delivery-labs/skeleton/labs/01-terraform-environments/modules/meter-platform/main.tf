# One customer environment for MeterFlow: network, cluster, database, monitoring.
#
# Environments differ only through the profile below. Reading this table tells you, and the
# customer, exactly how dev differs from prod and why non-production costs less.

locals {
  profiles = {
    dev = {
      zones          = ["1"]
      aks_sku_tier   = "Free"
      system_pool    = { vm_size = "Standard_D2s_v5", min_count = 1, max_count = 2 }
      workload_pool  = { vm_size = "Standard_D4s_v5", min_count = 1, max_count = 3 }
      pg_sku         = "B_Standard_B2s"
      pg_storage_mb  = 32768
      pg_ha          = false
      pg_geo_backup  = false
      pg_retention   = 7
      log_retention  = 30
      dr_replication = false
    }
    uat = {
      zones          = ["1", "2", "3"]
      aks_sku_tier   = "Standard"
      system_pool    = { vm_size = "Standard_D2s_v5", min_count = 1, max_count = 3 }
      workload_pool  = { vm_size = "Standard_D4s_v5", min_count = 1, max_count = 3 }
      pg_sku         = "GP_Standard_D2ds_v5"
      pg_storage_mb  = 65536
      pg_ha          = false
      pg_geo_backup  = false
      pg_retention   = 7
      log_retention  = 30
      dr_replication = false
    }
    staging = {
      zones          = ["1", "2", "3"]
      aks_sku_tier   = "Standard"
      system_pool    = { vm_size = "Standard_D4s_v5", min_count = 3, max_count = 5 }
      workload_pool  = { vm_size = "Standard_D8s_v5", min_count = 3, max_count = 9 }
      pg_sku         = "GP_Standard_D4ds_v5"
      pg_storage_mb  = 262144
      pg_ha          = true
      pg_geo_backup  = false
      pg_retention   = 7
      log_retention  = 30
      dr_replication = true
    }
    prod = {
      zones          = ["1", "2", "3"]
      aks_sku_tier   = "Standard"
      system_pool    = { vm_size = "Standard_D4s_v5", min_count = 3, max_count = 5 }
      workload_pool  = { vm_size = "Standard_D8s_v5", min_count = 3, max_count = 9 }
      pg_sku         = "GP_Standard_D4ds_v5"
      pg_storage_mb  = 1048576
      pg_ha          = true
      pg_geo_backup  = true
      pg_retention   = 35
      log_retention  = 90
      dr_replication = true
    }
  }

  profile     = local.profiles[var.environment]
  name_prefix = "${var.customer}-${var.environment}"

  tags = merge(var.tags, {
    customer    = var.customer
    environment = var.environment
    managed-by  = "terraform"
    workload    = "meterflow"
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

module "monitoring" {
  source = "../monitoring"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  retention_in_days   = local.profile.log_retention
  tags                = local.tags
}

module "network" {
  source = "../network"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.address_space
  customer_cidrs      = var.customer_cidrs
  meter_source_cidrs  = var.meter_source_cidrs
  ops_source_cidrs    = var.ops_source_cidrs
  hub_vnet_id         = var.hub_vnet_id
  firewall_private_ip = var.firewall_private_ip
  tags                = local.tags
}

module "aks" {
  source = "../aks"

  name_prefix                = local.name_prefix
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  node_subnet_id             = module.network.subnet_ids.aks_nodes
  zones                      = local.profile.zones
  sku_tier                   = local.profile.aks_sku_tier
  system_pool                = local.profile.system_pool
  workload_pool              = local.profile.workload_pool
  tenant_id                  = var.tenant_id
  admin_group_object_ids     = var.admin_group_object_ids
  log_analytics_workspace_id = module.monitoring.workspace_id
  outbound_type              = var.firewall_private_ip == null ? "loadBalancer" : "userDefinedRouting"
  tags                       = local.tags
}

module "postgres" {
  source = "../postgres"

  name_prefix           = "${local.name_prefix}${var.name_suffix}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  sku_name              = local.profile.pg_sku
  storage_mb            = local.profile.pg_storage_mb
  delegated_subnet_id   = module.network.subnet_ids.database
  private_dns_zone_id   = module.network.postgres_private_dns_zone_id
  high_availability     = local.profile.pg_ha
  geo_redundant_backup  = local.profile.pg_geo_backup
  backup_retention_days = local.profile.pg_retention
  logical_replication   = local.profile.dr_replication
  tenant_id             = var.tenant_id
  entra_admin           = var.db_admin
  tags                  = local.tags
}
