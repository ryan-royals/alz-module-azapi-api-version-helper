variable "latest_date_lock" {
  type        = string
  description = "This is used to lock to a latest at time of module creation. If not provided, the latest API version will be used each time."
  nullable    = true
  default     = null
  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.latest_date_lock)) || var.latest_date_lock == null
    error_message = "The latest_date_lock must be in the format 'YYYY-MM-DD'."
  }
}

locals {
  resource_types_all_versions = {
    "Microsoft.Network/privateDnsZones" = ["2020-06-01", "2024-06-01", "2020-01-01", "2018-09-01", "2040-12-31"]
  }
}

locals {
  date_lock = coalesce(var.latest_date_lock, formatdate("YYYY-MM-DD", timestamp()))
  timecmp = {
    for resource_type, versions in local.resource_types_all_versions : resource_type => reverse(sort(compact(flatten([
      for version in versions : [timecmp("${var.latest_date_lock}T00:00:00Z", "${version}T00:00:00Z") >= 0 ? version : null]
    ]))))
  }
}

output "latest_versions" {
  value = {
    for resource_type, versions in local.timecmp : resource_type => "${resource_type}@${versions[0]}"
  }
}
output "latest_versions_all" {
  value = {
    for resource_type, versions in local.timecmp : resource_type => [for version in versions : "${resource_type}@${version}"]
  }
}



