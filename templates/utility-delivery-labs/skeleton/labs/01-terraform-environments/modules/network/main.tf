# Spoke network for one customer environment.
# Every environment uses the same /20 layout, so dev looks like prod at a smaller scale.

locals {
  subnet_prefixes = {
    aks_nodes         = cidrsubnet(var.address_space, 2, 0) # /22, 1,024 addresses
    database          = cidrsubnet(var.address_space, 4, 4) # /24
    private_endpoints = cidrsubnet(var.address_space, 4, 5) # /24
    internal_lb       = cidrsubnet(var.address_space, 4, 6) # /24
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_prefixes.aks_nodes]
}

resource "azurerm_subnet" "database" {
  name                 = "snet-database"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_prefixes.database]

  delegation {
    name = "postgres-flexible"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_prefixes.private_endpoints]

  # Apply NSGs to private endpoints too, so access to Key Vault and the registry is filtered.
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "internal_lb" {
  name                 = "snet-internal-lb"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_prefixes.internal_lb]
}

# --- Network security groups -------------------------------------------------
# The AKS subnet only gets explicit allows for customer traffic. Pod-to-pod filtering is done by
# Kubernetes NetworkPolicy (Cilium), and egress by the hub firewall. A blanket deny here would also
# break node-to-node and overlay traffic that AKS needs.

resource "azurerm_network_security_group" "aks_nodes" {
  name                = "nsg-${var.name_prefix}-aks-nodes"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-meter-readings"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = var.meter_source_cidrs
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "8443"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nodes.id
}

# The database subnet is tighter: only the AKS nodes and the customer's jump hosts may reach 5432.
resource "azurerm_network_security_group" "database" {
  name                = "nsg-${var.name_prefix}-database"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-postgres-from-aks"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = local.subnet_prefixes.aks_nodes
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "5432"
  }

  security_rule {
    name                       = "allow-postgres-from-ops"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = var.ops_source_cidrs
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "5432"
  }

  security_rule {
    name                       = "deny-postgres-from-everything-else"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "5432"
  }
}

resource "azurerm_subnet_network_security_group_association" "database" {
  subnet_id                 = azurerm_subnet.database.id
  network_security_group_id = azurerm_network_security_group.database.id
}

# --- Egress through the hub firewall -----------------------------------------

resource "azurerm_route_table" "egress" {
  count = var.firewall_private_ip == null ? 0 : 1

  name                = "rt-${var.name_prefix}-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "aks_nodes" {
  count = var.firewall_private_ip == null ? 0 : 1

  subnet_id      = azurerm_subnet.aks_nodes.id
  route_table_id = azurerm_route_table.egress[0].id
}

# --- Hub peering ---------------------------------------------------------------
# Only the spoke-to-hub side is created here. The hub-to-spoke side lives in the hub team's
# configuration, because the hub is usually owned by the customer's network team.

resource "azurerm_virtual_network_peering" "to_hub" {
  count = var.hub_vnet_id == null ? 0 : 1

  name                      = "peer-${var.name_prefix}-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.hub_vnet_id
  allow_forwarded_traffic   = true
  use_remote_gateways       = var.use_remote_gateways
}

# --- Private DNS for PostgreSQL ------------------------------------------------
# Flexible Server with VNet integration needs a private zone ending in .postgres.database.azure.com.

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.name_prefix}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "link-${var.name_prefix}-postgres"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
