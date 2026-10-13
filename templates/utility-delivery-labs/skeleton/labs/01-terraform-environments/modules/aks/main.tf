# Private AKS cluster for MeterFlow.
# Design choices are explained in labs/00-approved-architecture/adr/.

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # ADR-005: private by default.
  private_cluster_enabled = var.private_cluster

  # People sign in through the customer's Entra ID only. No shared kubeconfig with a static
  # admin certificate exists, so access can be audited and revoked per person.
  local_account_disabled            = true
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    admin_group_object_ids = var.admin_group_object_ids
    azure_rbac_enabled     = true
  }

  # Workloads get Azure access through workload identity, so no client secrets exist.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Azure Policy add-on lets the customer's governance team enforce their own policies.
  azure_policy_enabled = true

  # Patch releases and node images are applied automatically; minor upgrades are planned changes.
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_pool.vm_size
    vnet_subnet_id               = var.node_subnet_id
    zones                        = var.zones
    auto_scaling_enabled         = true
    min_count                    = var.system_pool.min_count
    max_count                    = var.system_pool.max_count
    only_critical_addons_enabled = true
    tags                         = var.tags

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    outbound_type       = var.outbound_type
    load_balancer_sku   = "standard"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = var.tags

  lifecycle {
    # The cluster autoscaler owns the node count; without this every plan would show a diff.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "workload" {
  name                  = "workload"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = "User"
  vm_size               = var.workload_pool.vm_size
  vnet_subnet_id        = var.node_subnet_id
  zones                 = var.zones
  auto_scaling_enabled  = true
  min_count             = var.workload_pool.min_count
  max_count             = var.workload_pool.max_count
  tags                  = var.tags

  node_labels = {
    "workload" = "meterflow"
  }

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
