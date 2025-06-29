/**
 * Copyright 2025 Google LLC
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

data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "cloud_function/"
  output_path = "/tmp/function_source.zip"
}

resource "google_storage_bucket" "function_bucket" {
  project                     = var.project_id
  name                        = "${var.project_id}-cf-source-bucket"
  location                    = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "function_archive" {
  name   = "source_code.zip#${data.archive_file.function_source.output_md5}"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path 
}

resource "google_cloudfunctions2_function" "query_restarter_function" {
  project  = var.project_id
  location = var.region
  name     = var.cloud_function_name

  build_config {
    runtime     = "python311"
    entry_point = "restart_bq_continuous"
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_archive.name
      }
    }
    environment_variables = {
      GCP_PROJECT   = var.project_id
      BQ_JOB_PREFIX = var.continuous_query_job_prefix
    }
  }

  service_config {
    max_instance_count             = 1
    min_instance_count             = 1
    available_memory               = "256Mi"
    timeout_seconds                = 60
    service_account_email          = google_service_account.function_sa.email
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.log_sink_topic.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [
    google_service_account.function_sa,
    google_project_iam_member.function_sa_bq_job_user,
    google_pubsub_topic.log_sink_topic
  ]
}

# Service account for the Cloud Function to run as
resource "google_service_account" "function_sa" {
  project      = var.project_id
  account_id   = "${var.service_account_id}-cf" 
  display_name = "Service Account for Cloud Function BQ Job Restarter"
}

# Grant the Function SA permission to create BigQuery jobs
resource "google_project_iam_member" "function_sa_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Topic for the log sink to publish to, which triggers the Cloud Function
resource "google_pubsub_topic" "log_sink_topic" {
  project = var.project_id
  name    = "${var.pubsub_topic_id}-logs" 
}

resource "google_pubsub_topic_iam_member" "function_trigger_binding" {
  project = var.project_id
  topic   = google_pubsub_topic.log_sink_topic.name
  role    = "roles/pubsub.subscriber" 
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_service_account_iam_member" "function_bq_continuous" {
  service_account_id = google_service_account.continuous_query_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_service_account_iam_member" "function_sa_token_creator" {
  service_account_id = google_service_account.function_sa.name 
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcf-admin-robot.iam.gserviceaccount.com"
}
