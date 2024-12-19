# Initialising the lab
resource "random_pet" "name" {
  length = 2
}
variable "dns_zones_to_deploy" {
  type    = list(string)
  default = ["privatelink.blob.core.windows.net", "privatelink.file.core.windows.net"]
}
variable "decoy_dns_zones" {
  type    = list(string)
  default = ["privatelink.table.core.windows.net"]
}

data "azapi_client_config" "current" {}

resource "azapi_resource" "rg" {
  type     = "Microsoft.Resources/resourceGroups@2024-03-01"
  name     = "rg-${random_pet.name.id}"
  location = "australiaeast"
  body     = {}
}

resource "azapi_resource" "pdns_zones" {
  for_each  = toset(var.dns_zones_to_deploy)
  type      = "Microsoft.Network/privateDnsZones@2024-06-01"
  parent_id = azapi_resource.rg.id
  location  = "global"
  name      = each.key
  body      = {}
}

## Here we are just constructing the resource id for the DNS zones we want to check if they exist. 
## In a real world scenario this would be a list of resource ids that we already know and want to check if they are real.
locals {
  parent_id     = azapi_resource.rg.id
  resource_type = "Microsoft.Network/privateDnsZones"
  names         = concat(var.dns_zones_to_deploy, var.decoy_dns_zones)
  dns_zones_to_check_if_real = [
    for v in local.names : provider::azapi::build_resource_id(local.parent_id, local.resource_type, v)
  ]
}

resource "time_sleep" "_60s" {
  depends_on      = [azapi_resource.pdns_zones]
  create_duration = "60s"
}


###

# Below is the actual Lab code

# Problem case:
# We have a list of DNS zones that we want to check if they exist, as when interacting with Azure Policy, the Policy assumes they all do exist, and fails on the permissions apply.
# If we have a way to check for realness, we can then subtract bad entries from the list so we no longer get errors on the Apply step.

# Challenges:
# - Need to use `AzAPI` as we frequently cross subscription boundaries
# - `AzAPI` needs to know both resource_type and api_version when interacting with resources.

# Solution proposed here:
# Have a module that fills the gap in AzAPI where it does not have an awareness of API versions. Then using this information, use the `azapi_resource_list` to discover deployed resources.
# In the ALZ module, we can then add privateDnsZones to the `dependencies.role_assignments` block, and have this discover of deployed resources depend on that.




module "api_version_lookup" {
  # This little module takes a resource ID, and returns the valid API versions associated to that resource type, 
  # as AzAPI does not operate without having `resource_type@api_version` in the `type =` field.
  # 
  # Largest issue with this solution is the management overhead, as it should have a statically kept source of information, being the versions.
  # Untested, but assumed that if this used a more dynamic solution like a Provider, Terraform would get upset at Plan/Apply time in some use cases, which would lead to a poor user experience.
  # I have also frequently encountered that AzAPI Reference documentation != actual published, usable API. So if it was to be automated, we would need to validate and confirm each API.
  source           = "./api_version_lookup"
  latest_date_lock = "2024-12-19"
}

## Since we can measure against a resource ID, we can easily find the parent ID, which then gives us the information we need to do a scouting run with `AzAPI`
data "azapi_resource_list" "listByResourceGroup" {
  type                   = module.api_version_lookup.latest_versions["Microsoft.Network/privateDnsZones"]
  parent_id              = local.parent_id
  response_export_values = ["*"]
  depends_on             = [time_sleep._60s]
}
locals {
  all_found_dns_zones = [for o in data.azapi_resource_list.listByResourceGroup.output.value : o.id]
}

## Since we have the below information, we can do whatever we need to with it from here.
output "all_found_dns_zones" {
  value = local.all_found_dns_zones
}
output "found_dns_zones" {
  value = [for v in local.dns_zones_to_check_if_real : v if contains(local.all_found_dns_zones, v)]
}
output "not_found_dns_zones" {
  value = [for v in local.dns_zones_to_check_if_real : v if !contains(local.all_found_dns_zones, v)]
}
