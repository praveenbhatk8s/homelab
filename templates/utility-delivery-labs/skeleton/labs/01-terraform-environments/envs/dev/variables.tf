variable "subscription_id" {
  description = "Azure subscription for this environment."
  type        = string
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

variable "hub_vnet_id" {
  description = "Hub VNet to peer with. Null for an isolated sandbox."
  type        = string
  default     = null
}

variable "firewall_private_ip" {
  description = "Hub firewall IP. Null for direct egress in a sandbox."
  type        = string
  default     = null
}

variable "name_suffix" {
  description = "Suffix for globally unique names, for example -a1b2."
  type        = string
  default     = ""
}
