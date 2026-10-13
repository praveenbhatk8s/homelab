# uat environment for Stadtwerke Talheim.
# Everything that differs from other environments is on this page or in modules/meter-platform's profile.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Partial configuration: run terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

module "platform" {
  source = "../../modules/meter-platform"

  customer    = "talheim"
  environment = "uat"
  location    = "germanywestcentral"

  address_space      = "10.42.0.0/20"
  customer_cidrs     = ["10.10.0.0/16", "100.64.0.0/16"]
  meter_source_cidrs = ["100.64.0.0/16"]
  ops_source_cidrs   = ["10.10.5.0/24"]

  hub_vnet_id         = var.hub_vnet_id
  firewall_private_ip = var.firewall_private_ip

  tenant_id              = var.tenant_id
  admin_group_object_ids = var.admin_group_object_ids
  db_admin               = var.db_admin
  name_suffix            = var.name_suffix

  tags = {
    cost-centre = "meterflow-uat"
  }
}

output "resilience" {
  value = module.platform.resilience
}

output "aks_cluster_name" {
  value = module.platform.aks_cluster_name
}

output "postgres_fqdn" {
  value = module.platform.postgres_fqdn
}
