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

resource "google_service_account" "continuous_query_sa" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Service Account for BigQuery Continuous Query"
}

# Grant permissions to read from the BigQuery ingestion table
resource "google_project_iam_member" "bq_table_reader" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.continuous_query_sa.email}"
}

resource "google_project_iam_member" "bq_table_user" {
  project = var.project_id
  role    = "roles/bigquery.user" # Required to read table data & metadata
  member  = "serviceAccount:${google_service_account.continuous_query_sa.email}"
}

# Grant permissions to access to the Pub/Sub topic
resource "google_pubsub_topic_iam_member" "pubsub_editor" {
  project = var.project_id
  topic   = google_pubsub_topic.continuous_query_topic.name
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.continuous_query_sa.email}"
}

# Grant permissions to create BigQuery jobs
resource "google_project_iam_member" "bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.continuous_query_sa.email}"
}

# --- IAM for Cloud Function V2 and Eventarc ---

# 1. Grant the Function's Service Account `roles/eventarc.eventReceiver`
# This allows the function's service account to receive events forwarded by Eventarc.
resource "google_project_iam_member" "function_sa_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

data "google_project" "project" {
  project_id = var.project_id
}

# 2. The Eventarc service agent also needs to be able to create service account tokens for the function's identity
#    to impersonate it when invoking the function. This is `roles/iam.serviceAccountTokenCreator` on the function's service account.
resource "google_service_account_iam_member" "eventarc_sa_token_creator_on_function_sa" {
  service_account_id = google_service_account.function_sa.name // Fully qualified name for service_account_id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
  depends_on         = [google_service_account.function_sa]
}
