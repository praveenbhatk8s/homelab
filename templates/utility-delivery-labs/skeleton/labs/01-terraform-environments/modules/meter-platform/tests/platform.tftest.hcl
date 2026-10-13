# Tests the environment profiles: the promises made to the customer about how each environment behaves.

mock_provider "azurerm" {}

variables {
  customer           = "talheim"
  environment        = "prod"
  address_space      = "10.44.0.0/20"
  customer_cidrs     = ["10.10.0.0/16", "100.64.0.0/16"]
  meter_source_cidrs = ["100.64.0.0/16"]
  ops_source_cidrs   = ["10.10.5.0/24"]
  tenant_id          = "00000000-0000-0000-0000-000000000001"
  admin_group_object_ids = [
    "00000000-0000-0000-0000-000000000002",
  ]

  db_admin = {
    object_id      = "00000000-0000-0000-0000-000000000003"
    principal_name = "sg-talheim-dba"
    principal_type = "Group"
  }
}

run "prod_is_zone_redundant_end_to_end" {
  command = plan

  assert {
    condition     = output.resilience.zones == tolist(["1", "2", "3"])
    error_message = "Prod node pools must span three zones."
  }

  assert {
    condition     = output.resilience.database_ha == true
    error_message = "Prod database must be zone-redundant."
  }

  assert {
    condition     = output.resilience.backup_retention_days == 35
    error_message = "Prod must keep 35 days of point-in-time restore."
  }

  assert {
    condition     = output.resilience.private_cluster == true
    error_message = "Prod cluster must be private."
  }
}

run "prod_replicates_to_dr" {
  command = plan

  assert {
    condition     = output.profile.dr_replication == true
    error_message = "Prod must enable logical replication for the DR site (ADR-003)."
  }
}

run "dev_is_cheap_and_says_so" {
  command = plan

  variables {
    environment   = "dev"
    address_space = "10.41.0.0/20"
  }

  assert {
    condition     = length(output.resilience.zones) == 1 && output.resilience.database_ha == false
    error_message = "Dev should use one zone and no database HA, to keep cost down."
  }
}

run "egress_uses_firewall_routing_when_a_firewall_is_given" {
  command = plan

  variables {
    firewall_private_ip = "10.40.0.4"
  }

  assert {
    condition     = output.resilience.egress_via_firewall == true
    error_message = "Egress should route through the firewall."
  }
}

run "refuses_regions_outside_germany" {
  command = plan

  variables {
    location = "westeurope"
  }

  expect_failures = [var.location]
}

run "refuses_unknown_environments" {
  command = plan

  variables {
    environment = "test"
  }

  expect_failures = [var.environment]
}
