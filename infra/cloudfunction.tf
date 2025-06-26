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
  project = var.project_id
  name    = "${var.project_id}-cf-source-bucket" # Bucket names must be globally unique
  location = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "function_archive" {
  name   = "source_code.zip#${data.archive_file.function_source.output_md5}" # Add MD5 to trigger updates on code change
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path # Path to the zipped function source
}

resource "google_cloudfunctions_function" "job_restarter_function" {
  project = var.project_id
  name    = var.cloud_function_name
  region  = var.region
  runtime = "python311" 

  description = "Restarts a BigQuery continuous query job if it fails with a 'cancelled' status."
  entry_point = "restart_bq_job" # The function name in your Python code

  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.function_archive.name

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.log_sink_topic.name 
  }

  environment_variables = {
    GCP_PROJECT   = var.project_id
    BQ_JOB_PREFIX = var.continuous_query_job_prefix
  }

  # Service account for the Cloud Function itself
  # This SA needs permissions to:
  # 1. Read from the Pub/Sub topic (trigger). This is usually granted by default.
  # 2. Submit BigQuery jobs (to restart the continuous query).
  # 3. (Optional) Write logs to Cloud Logging.
  service_account_email = google_service_account.function_sa.email

  depends_on = [
    google_service_account.function_sa,
    google_project_iam_member.function_sa_bq_job_user,
    google_pubsub_topic.log_sink_topic // Ensure topic exists before function creation
  ]
}

# Service account for the Cloud Function to run as
resource "google_service_account" "function_sa" {
  project      = var.project_id
  account_id   = "${var.service_account_id}-cf" # Differentiate from the BQ SA
  display_name = "Service Account for Cloud Function BQ Job Restarter"
}

# Grant the Function SA permission to create BigQuery jobs
resource "google_project_iam_member" "function_sa_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant the Function SA permission to be invoked by Pub/Sub (via the log sink)
# This is often implicitly handled or might need roles/cloudfunctions.invoker if you have strict IAM
# For Pub/Sub triggers, the Cloud Functions service agent usually handles this.
# However, explicit grant for the function's SA to use the topic is good practice.

# Topic for the log sink to publish to, which triggers the Cloud Function
resource "google_pubsub_topic" "log_sink_topic" {
  project = var.project_id
  name    = "${var.pubsub_topic_id}-logs" # e.g., tf_continuous_query_topic-logs
}

# Allow the Log Sink's writer identity to publish to this topic
# This will be configured in the log_sink.tf file using the sink's writer identity output.
# We define the topic here so the function can reference it.

# Allow the Cloud Function service account to read from (be triggered by) this log topic
resource "google_pubsub_topic_iam_member" "function_trigger_binding" {
  project = var.project_id
  topic   = google_pubsub_topic.log_sink_topic.name
  role    = "roles/pubsub.subscriber" # Or a more specific role if available like roles/cloudfunctions.invoker on the function
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Also, the default Cloud Functions service agent for your project needs to be able to create tokens for the function's service account to impersonate it.
# This is usually `service-[PROJECT_NUMBER]@gcf-admin-robot.iam.gserviceaccount.com`
# And it needs the `roles/iam.serviceAccountTokenCreator` on the function's service account (`google_service_account.function_sa.email`).

resource "google_service_account_iam_member" "function_sa_token_creator" {
  service_account_id = google_service_account.function_sa.name // Fully qualified name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcf-admin-robot.iam.gserviceaccount.com"
}

data "google_project" "project" {
 project_id = var.project_id
}
