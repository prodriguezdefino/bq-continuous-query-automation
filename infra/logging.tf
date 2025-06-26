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

 resource "google_logging_project_sink" "bq_job_error_sink" {
  project = var.project_id
  name    = "bq_continuous_query_error_sink"
  # Filter for BigQuery job completion events, specifically for jobs with the defined prefix,
  # and that have an error status.
  filter  = <<-EOT
resource.type="bigquery_resource"
protoPayload.methodName="jobservice.jobcompleted"
protoPayload.serviceData.jobCompletedEvent.job.jobName.jobId:"${var.continuous_query_job_prefix}"
protoPayload.serviceData.jobCompletedEvent.job.jobStatus.error.message:*
EOT

  # Send to the Pub/Sub topic that triggers the Cloud Function
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.log_sink_topic.name}"

  # The log sink needs permissions to publish to the Pub/Sub topic.
  # This is granted by giving the sink's writer identity the 'roles/pubsub.publisher' role on the topic.
  # Terraform can grant this automatically if 'unique_writer_identity' is true.
  unique_writer_identity = true

  depends_on = [google_pubsub_topic.log_sink_topic]
}

# Grant the sink's writer identity permission to publish to the log sink's Pub/Sub topic
resource "google_pubsub_topic_iam_member" "log_sink_writer" {
  project = var.project_id
  topic   = google_pubsub_topic.log_sink_topic.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.bq_job_error_sink.writer_identity
}
