variable "name_prefix" {
  description = "Short prefix for resource names, for example talheim-prod."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 characters of lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the network."
  type        = string
}

variable "customer_cidrs" {
  description = "Every address range the customer uses on-prem or in their APN. The spoke must not overlap any of them."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.customer_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in customer_cidrs must be a valid CIDR."
  }
}

variable "address_space" {
  description = "The spoke's address space. Must be a /20 and must not overlap any customer range."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && try(tonumber(split("/", var.address_space)[1]) == 20, false)
    error_message = "address_space must be a valid /20 CIDR, so every environment has the same subnet layout."
  }

  # Two CIDRs overlap when their network addresses match at the shorter of the two prefix lengths.
  # cidrhost(x, 0) gives the network address of x, so re-reading both at that prefix compares them.
  validation {
    condition = alltrue([
      for c in var.customer_cidrs :
      cidrhost("${split("/", var.address_space)[0]}/${min(tonumber(split("/", var.address_space)[1]), tonumber(split("/", c)[1]))}", 0)
      != cidrhost("${split("/", c)[0]}/${min(tonumber(split("/", var.address_space)[1]), tonumber(split("/", c)[1]))}", 0)
    ])
    error_message = "address_space overlaps a customer range in customer_cidrs. Routing across the VPN would break; choose another range."
  }
}

variable "meter_source_cidrs" {
  description = "Ranges allowed to send meter readings (concentrators behind the APN)."
  type        = list(string)
}

variable "ops_source_cidrs" {
  description = "Ranges allowed to reach the database for operations (customer jump hosts)."
  type        = list(string)
}

variable "hub_vnet_id" {
  description = "ID of the hub VNet to peer with. Null skips peering, for example in an isolated test."
  type        = string
  default     = null
}

variable "use_remote_gateways" {
  description = "Use the hub's VPN gateway for routes to the customer network. Requires a gateway in the hub."
  type        = bool
  default     = true
}

variable "firewall_private_ip" {
  description = "Private IP of the hub firewall. When set, all egress from the AKS subnet is routed through it."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
