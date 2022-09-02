/**
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  random_id = var.random_id != null ? var.random_id : random_id.default.hex
  project = (var.create_project
    ? try(module.project_radlab_gen_cromwell.0, null)
    : try(data.google_project.existing_project.0, null)
  )

  region = var.default_region

  network = (
    var.create_network
    ? try(module.vpc_cromwell.0.network.network, null)
    : try(data.google_compute_network.default.0, null)
  )

  subnet = (
    var.create_network
    ? try(module.vpc_cromwell.0.subnets["${local.region}/${var.network_name}"], null)
    : try(data.google_compute_subnetwork.default.0, null)
  )

  project_services = var.enable_services ? [
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "servicenetworking.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "iam.googleapis.com",
    "lifesciences.googleapis.com"
  ] : []
}

resource "random_id" "default" {
  byte_length = 2
}

####################
# Cromwell Project #
####################

data "google_project" "existing_project" {
  count      = var.create_project ? 0 : 1
  project_id = var.project_name
}

module "project_radlab_gen_cromwell" {
  count   = var.create_project ? 1 : 0
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 13.0"

  name              = var.use_random_id ? format("%s-%s", var.project_name, local.random_id) : var.project_name
  random_project_id = false
  folder_id         = var.folder_id
  billing_account   = var.billing_account_id
  org_id            = var.organization_id
  labels = {
    vpc-network = var.network_name
  }

  activate_apis = []
}

resource "google_project_service" "enabled_services" {
  for_each                   = toset(local.project_services)
  project                    = local.project.project_id
  service                    = each.value
  disable_dependent_services = true
  disable_on_destroy         = true

  depends_on = [
    module.project_radlab_gen_cromwell
  ]
}

resource "time_sleep" "wait_enabled_services" {
  depends_on = [
    google_project_service.enabled_services,
  ]

  create_duration = "120s"
}

resource "google_storage_bucket" "cromwell_workflow_bucket" {
  name                        = "${local.project.project_id}-cromwell-wf-exec"
  location                    = local.region
  force_destroy               = true
  uniform_bucket_level_access = true
  project                     = local.project.project_id

  cors {
    origin          = ["http://user-scripts"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  depends_on = [
    time_sleep.wait_enabled_services
  ]
}

resource "google_storage_bucket_object" "config" {
  name   = "provisioning/cromwell.conf"
  bucket = google_storage_bucket.cromwell_workflow_bucket.name
  content = templatefile("scripts/build/cromwell.conf", {
    CROMWELL_PROJECT         = local.project.project_id,
    CROMWELL_ROOT_BUCKET     = google_storage_bucket.cromwell_workflow_bucket.url,
    CROMWELL_VPC             = var.network_name
    CROMWELL_SERVICE_ACCOUNT = module.cromwell_service_account.email,
    CROMWELL_PAPI_LOCATION   = var.cromwell_PAPI_location,
    CROMWELL_PAPI_ENDPOINT   = var.cromwell_PAPI_endpoint,
    REQUESTER_PAY_PROJECT    = local.project.project_id,
    CROMWELL_ZONES           = "[${join(", ", var.cromwell_zones)}]"
    CROMWELL_PORT            = var.cromwell_port,
    CROMWELL_DB_IP           = module.cromwell_mysql_db.instance_ip_address[0].ip_address,
    CROMWELL_DB_PASS         = random_password.cromwell_db_pass.result
  })
}

resource "google_storage_bucket_object" "bootstrap" {
  name   = "provisioning/bootstrap.sh"
  bucket = google_storage_bucket.cromwell_workflow_bucket.name
  content = templatefile("scripts/build/bootstrap.sh", {
    CROMWELL_VERSION = var.cromwell_version,
    BUCKET_URL       = google_storage_bucket.cromwell_workflow_bucket.url
  })
}

resource "google_storage_bucket_object" "service" {
  name   = "provisioning/cromwell.service"
  source = "scripts/build/cromwell.service"
  bucket = google_storage_bucket.cromwell_workflow_bucket.name
}

resource "google_billing_budget" "budget" {
  billing_account = var.billing_account_id
  display_name    = "Billing Budget for ${var.project_name} project"

  budget_filter {
    projects = ["projects/${var.project_name}"]
    custom_period { 
      start_date {
        year = var.budget_start_date_year
        month = var.budget_start_date_month
        day = var.budget_start_date_day
      }
      end_date {
        year = var.budget_end_date_year
        month = var.budget_end_date_month
        day = var.budget_end_date_day
      }
    }
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency_code
      units         = var.budget_amount
    }
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.25
  }

  all_updates_rule {
    monitoring_notification_channels = [
      google_monitoring_notification_channel.scientist_notification_channel.id,
      google_monitoring_notification_channel.manager_notification_channel.id
    ]
    disable_default_iam_recipients = true
  }
}

resource "google_monitoring_notification_channel" "scientist_notification_channel" {
  display_name = "Budget Notification Channel for scientist"
  type         = "email"
  project      = module.project_radlab_genomics.project_id

  labels = {
    email_address = var.owner
  }
}

resource "google_monitoring_notification_channel" "manager_notification_channel" {
  display_name = "Budget Notification Channel for manager"
  type         = "email"
  project      = module.project_radlab_genomics.project_id

  labels = {
    email_address = var.manager
  }
}