/**
 * Copyright 2022 Google LLC
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


output "deployment_id" {
  description = "RADLab Module Deployment ID"
  value       = var.deployment_id
}

output "project_id" {
  description = "Genomics Project ID"
  value       = local.project.project_id
}

output "input_bucket" {
  description = "Input GCS bucket to which to upload fastq or fastq.qz files."
  value       = google_storage_bucket.input_bucket.name
}

output "output_bucket" {
  description = "Output GCS bucket in which QC reports and execution logs are stored."
  value       = google_storage_bucket.output_bucket.name
}
