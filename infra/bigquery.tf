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

resource "google_bigquery_dataset" "ingestion_dataset" {
  project     = var.project_id
  dataset_id  = var.dataset_id
  location    = var.bq_region
  description = "Dataset for ingesting data for the continuous query."
}

resource "google_bigquery_table" "ingestion_table" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.ingestion_dataset.dataset_id
  table_id   = var.ingestion_table_id

  schema = <<EOF
[
  {
    "name": "message",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "The message content"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "description": "The time for this row"
  }
]
EOF

  deletion_protection = false 
}

locals {
  bq_job_id = "${var.continuous_query_job_prefix}init5"
}

resource "null_resource" "create_continuous_query_job" {

  triggers = {
    "job_name" = local.bq_job_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      bq query \
        --project_id=${var.project_id} \
        --job_id="${local.bq_job_id}" \
        --use_legacy_sql=false \
        --continuous \
        --synchronous_mode=false \
        --connection_property=service_account=${google_service_account.continuous_query_sa.email} \
        "EXPORT DATA OPTIONS ( \
          format = 'CLOUD_PUBSUB', \
          uri = 'https://pubsub.googleapis.com/projects/${var.project_id}/topics/${var.pubsub_topic_id}') \
        AS ( \
        SELECT TO_JSON_STRING(STRUCT(message, timestamp)) AS message_payload \
        FROM APPENDS(TABLE ${var.dataset_id}.${var.ingestion_table_id}, CURRENT_TIMESTAMP() - INTERVAL 1 SECOND));"
    EOT
  }

  depends_on = [
    google_bigquery_table.ingestion_table,
    google_pubsub_topic.continuous_query_topic,
    google_service_account.continuous_query_sa,
    google_project_iam_member.bq_table_reader,
    google_project_iam_member.bq_table_user,
    google_pubsub_topic_iam_member.pubsub_editor,
    google_project_iam_member.bq_job_user,
    google_bigquery_reservation_assignment.continuous_slots_assignment
  ]
}
