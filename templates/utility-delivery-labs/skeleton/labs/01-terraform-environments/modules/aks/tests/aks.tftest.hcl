mock_provider "azurerm" {}

variables {
  name_prefix                = "talheim-prod"
  location                   = "germanywestcentral"
  resource_group_name        = "rg-talheim-prod"
  node_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-talheim-prod/providers/Microsoft.Network/virtualNetworks/vnet-talheim-prod/subnets/snet-aks-nodes"
  tenant_id                  = "00000000-0000-0000-0000-000000000001"
  admin_group_object_ids     = ["00000000-0000-0000-0000-000000000002"]
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-talheim-prod/providers/Microsoft.OperationalInsights/workspaces/log-talheim-prod"

  system_pool = {
    vm_size   = "Standard_D4s_v5"
    min_count = 3
    max_count = 5
  }

  workload_pool = {
    vm_size   = "Standard_D8s_v5"
    min_count = 3
    max_count = 9
  }
}

run "cluster_is_private_with_no_local_accounts" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled == true
    error_message = "The API server must be private (ADR-005)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "Local accounts must be disabled so all access goes through Entra ID."
  }
}

run "workloads_use_identity_not_secrets" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.workload_identity_enabled && azurerm_kubernetes_cluster.this.oidc_issuer_enabled
    error_message = "Workload identity and the OIDC issuer must be enabled."
  }
}

run "network_policy_is_enforced" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium"
    error_message = "A network policy engine is required for default-deny NetworkPolicies."
  }
}

run "node_pools_span_three_zones_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.default_node_pool[0].zones) == 3
    error_message = "System pool should span three zones."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.workload.zones) == 3
    error_message = "Workload pool should span three zones."
  }
}

run "system_pool_only_runs_critical_addons" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled == true
    error_message = "Application pods must not land on the system pool."
  }
}

run "rejects_empty_admin_groups" {
  command = plan

  variables {
    admin_group_object_ids = []
  }

  expect_failures = [var.admin_group_object_ids]
}

run "rejects_unknown_sku_tier" {
  command = plan

  variables {
    sku_tier = "Basic"
  }

  expect_failures = [var.sku_tier]
}
