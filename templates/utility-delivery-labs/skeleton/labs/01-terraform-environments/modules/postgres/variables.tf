variable "name_prefix" {
  description = "Short prefix for resource names. Server names are global, so add a suffix if the name is taken."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the server."
  type        = string
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["15", "16", "17"], var.postgres_version)
    error_message = "postgres_version must be 15, 16 or 17."
  }
}

variable "sku_name" {
  description = "Compute SKU, for example B_Standard_B2s for dev or GP_Standard_D4ds_v5 for prod."
  type        = string
}

variable "storage_mb" {
  description = "Initial storage. Auto-grow is enabled, so this is a floor, not a ceiling."
  type        = number
  default     = 32768

  validation {
    condition     = contains([32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4193280, 4194304, 8388608, 16777216, 33553408], var.storage_mb)
    error_message = "storage_mb must be one of the sizes Flexible Server supports, for example 32768 or 1048576."
  }
}

variable "delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ending in .postgres.database.azure.com, linked to the VNet."
  type        = string
}

variable "high_availability" {
  description = "Zone-redundant HA with a standby in another zone. Not available on Burstable SKUs."
  type        = bool
  default     = false
}

variable "primary_zone" {
  description = "Zone for the primary server."
  type        = string
  default     = "1"
}

variable "standby_zone" {
  description = "Zone for the HA standby. Must differ from primary_zone."
  type        = string
  default     = "2"
}

variable "backup_retention_days" {
  description = "Point-in-time restore window."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "geo_redundant_backup" {
  description = "Copy backups to the paired region. Can only be set when the server is created."
  type        = bool
  default     = false
}

variable "logical_replication" {
  description = "Set wal_level=logical so the DR site can subscribe (ADR-003)."
  type        = bool
  default     = false
}

variable "tenant_id" {
  description = "Entra ID tenant for database authentication."
  type        = string
}

variable "entra_admin" {
  description = "Entra ID group or user that administers the server."
  type = object({
    object_id      = string
    principal_name = string
    principal_type = string
  })

  validation {
    condition     = contains(["Group", "User", "ServicePrincipal"], var.entra_admin.principal_type)
    error_message = "entra_admin.principal_type must be Group, User or ServicePrincipal."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
