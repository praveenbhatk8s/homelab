variable "customer" {
  description = "Short customer code used in names, for example talheim."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.customer))
    error_message = "customer must be 3-10 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Environment name. Selects the size and resilience profile."
  type        = string

  validation {
    condition     = contains(["dev", "uat", "staging", "prod"], var.environment)
    error_message = "environment must be dev, uat, staging or prod."
  }
}

variable "location" {
  description = "Azure region. Restricted to German regions because meter data must stay in Germany."
  type        = string
  default     = "germanywestcentral"

  validation {
    condition     = contains(["germanywestcentral", "germanynorth"], var.location)
    error_message = "Meter data must stay in Germany: location must be germanywestcentral or germanynorth."
  }
}

variable "address_space" {
  description = "The environment's /20 spoke."
  type        = string
}

variable "customer_cidrs" {
  description = "All customer ranges, to guard against overlap."
  type        = list(string)
}

variable "meter_source_cidrs" {
  description = "Ranges allowed to send meter readings."
  type        = list(string)
}

variable "ops_source_cidrs" {
  description = "Ranges allowed operations access to the database."
  type        = list(string)
}

variable "hub_vnet_id" {
  description = "Hub VNet to peer with, or null."
  type        = string
  default     = null
}

variable "firewall_private_ip" {
  description = "Hub firewall IP for egress, or null for direct egress."
  type        = string
  default     = null
}

variable "tenant_id" {
  description = "Customer Entra ID tenant."
  type        = string
}

variable "admin_group_object_ids" {
  description = "Entra ID groups with cluster-admin."
  type        = list(string)
}

variable "db_admin" {
  description = "Entra ID principal that administers PostgreSQL."
  type = object({
    object_id      = string
    principal_name = string
    principal_type = string
  })
}

variable "name_suffix" {
  description = "Optional suffix for globally unique names such as the PostgreSQL server."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags. Customer, environment and managed-by tags are always added."
  type        = map(string)
  default     = {}
}
