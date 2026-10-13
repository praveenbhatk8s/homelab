# Run with: terraform init -backend=false && terraform test
# The mock provider means no Azure account or credentials are needed.

mock_provider "azurerm" {}

variables {
  name_prefix         = "talheim-dev"
  location            = "germanywestcentral"
  resource_group_name = "rg-talheim-dev"
  address_space       = "10.41.0.0/20"
  customer_cidrs      = ["10.10.0.0/16", "100.64.0.0/16"]
  meter_source_cidrs  = ["100.64.0.0/16"]
  ops_source_cidrs    = ["10.10.5.0/24"]
}

run "subnets_follow_the_standard_layout" {
  command = plan

  assert {
    condition     = azurerm_subnet.aks_nodes.address_prefixes[0] == "10.41.0.0/22"
    error_message = "AKS node subnet should be the first /22 of the spoke."
  }

  assert {
    condition     = azurerm_subnet.database.address_prefixes[0] == "10.41.4.0/24"
    error_message = "Database subnet should be 10.41.4.0/24."
  }

  assert {
    condition     = azurerm_subnet.private_endpoints.address_prefixes[0] == "10.41.5.0/24"
    error_message = "Private endpoint subnet should be 10.41.5.0/24."
  }

  assert {
    condition     = azurerm_subnet.internal_lb.address_prefixes[0] == "10.41.6.0/24"
    error_message = "Internal load balancer subnet should be 10.41.6.0/24."
  }
}

run "database_subnet_is_delegated_to_postgres" {
  command = plan

  assert {
    condition     = azurerm_subnet.database.delegation[0].service_delegation[0].name == "Microsoft.DBforPostgreSQL/flexibleServers"
    error_message = "The database subnet must be delegated to PostgreSQL Flexible Server."
  }
}

run "postgres_is_only_reachable_from_aks_and_ops" {
  command = plan

  assert {
    condition     = length([for r in azurerm_network_security_group.database.security_rule : r if r.access == "Allow"]) == 2
    error_message = "Exactly two allow rules should exist on the database subnet: AKS and ops."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.database.security_rule :
      r.name == "allow-postgres-from-aks" && r.source_address_prefix == "10.41.0.0/22"
    ])
    error_message = "The AKS allow rule must be scoped to the AKS node subnet only."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.database.security_rule :
      r.access == "Deny" && r.destination_port_range == "5432" && r.source_address_prefix == "*"
    ])
    error_message = "A catch-all deny for 5432 must exist below the allow rules."
  }
}

run "no_egress_route_without_a_firewall" {
  command = plan

  assert {
    condition     = length(azurerm_route_table.egress) == 0
    error_message = "No route table should exist when no firewall IP is given."
  }
}

run "egress_goes_through_the_firewall_when_given" {
  command = plan

  variables {
    firewall_private_ip = "10.40.0.4"
  }

  assert {
    condition     = one(azurerm_route_table.egress[0].route).next_hop_in_ip_address == "10.40.0.4"
    error_message = "Default route should point at the firewall."
  }
}

run "rejects_a_spoke_that_overlaps_the_customer_network" {
  command = plan

  variables {
    address_space = "10.10.16.0/20"
  }

  expect_failures = [var.address_space]
}

run "rejects_a_spoke_that_contains_a_customer_range" {
  command = plan

  variables {
    customer_cidrs = ["10.41.3.0/24"]
  }

  expect_failures = [var.address_space]
}

run "rejects_a_spoke_of_the_wrong_size" {
  command = plan

  variables {
    address_space = "10.41.0.0/16"
  }

  expect_failures = [var.address_space]
}
