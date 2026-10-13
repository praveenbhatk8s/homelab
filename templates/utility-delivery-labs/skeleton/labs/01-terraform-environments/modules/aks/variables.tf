variable "name_prefix" {
  description = "Short prefix for resource names, for example talheim-prod."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, for example 1.33. Patch versions are applied by the auto-upgrade channel. Null uses the AKS default."
  type        = string
  default     = null
}

variable "node_subnet_id" {
  description = "Subnet for the node pools."
  type        = string
}

variable "zones" {
  description = "Availability zones for the node pools."
  type        = list(string)
  default     = ["1", "2", "3"]

  validation {
    condition     = length(var.zones) > 0 && alltrue([for z in var.zones : contains(["1", "2", "3"], z)])
    error_message = "zones must be a non-empty list drawn from 1, 2 and 3."
  }
}

variable "sku_tier" {
  description = "AKS control plane tier. Standard gives a financially backed uptime SLA; use it for anything customers depend on."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "system_pool" {
  description = "System node pool: runs only critical add-ons."
  type = object({
    vm_size   = string
    min_count = number
    max_count = number
  })

  validation {
    condition     = var.system_pool.min_count >= 1 && var.system_pool.max_count >= var.system_pool.min_count
    error_message = "system_pool needs min_count >= 1 and max_count >= min_count."
  }
}

variable "workload_pool" {
  description = "User node pool for MeterFlow and other workloads."
  type = object({
    vm_size   = string
    min_count = number
    max_count = number
  })

  validation {
    condition     = var.workload_pool.min_count >= 1 && var.workload_pool.max_count >= var.workload_pool.min_count
    error_message = "workload_pool needs min_count >= 1 and max_count >= min_count."
  }
}

variable "tenant_id" {
  description = "Entra ID tenant of the customer."
  type        = string
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that get cluster-admin. Must not be empty, because local accounts are disabled."
  type        = list(string)

  validation {
    condition     = length(var.admin_group_object_ids) > 0
    error_message = "At least one admin group is required; with local accounts disabled, nobody could administer the cluster otherwise."
  }
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for container insights."
  type        = string
}

variable "private_cluster" {
  description = "Make the API server private. Should only be false in a throwaway sandbox."
  type        = bool
  default     = true
}

variable "outbound_type" {
  description = "loadBalancer for direct egress, userDefinedRouting when the subnet routes through a firewall."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting"], var.outbound_type)
    error_message = "outbound_type must be loadBalancer or userDefinedRouting."
  }
}

variable "pod_cidr" {
  description = "Pod overlay range. Not routed outside the cluster, but must not clash with ranges pods need to reach."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service range."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "Cluster DNS IP, inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
