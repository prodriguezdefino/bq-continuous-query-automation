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
  project    = var.project_id
  dataset_id = var.dataset_id
  location   = var.region
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

  deletion_protection = false # Set to true for production environments
}

resource "google_bigquery_job" "continuous_query_job" {
  project = var.project_id
  location = var.region
  job_id_prefix = var.continuous_query_job_prefix 

  query {
    query = <<SQL
CREATE OR REPLACE CONTINUOUS QUERY `${var.project_id}.${var.dataset_id}.${var.continuous_query_job_prefix}continuous_query`
OPTIONS (
  service_account = "${google_service_account.continuous_query_sa.email}",
  interval = 15 MINUTE,  // How often the query runs
  max_parallelism = 1    // Number of parallel executions
)
AS
SELECT
  message,
  timestamp
FROM
  `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}`
WHERE
  timestamp > (SELECT MAX(timestamp) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}` WHERE _PARTITIONTIME = (SELECT MAX(_PARTITIONTIME) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}`))
  OR
  (SELECT MAX(timestamp) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}` WHERE _PARTITIONTIME = (SELECT MAX(_PARTITIONTIME) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}`)) IS NULL;

EXPORT DATA OPTIONS(
  uri = 'pubsub://${var.project_id}/${var.pubsub_topic_id}',
  format = 'JSON'
) AS
SELECT
  message,
  timestamp
FROM
  `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}`
WHERE
  timestamp > (SELECT MAX(timestamp) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}` WHERE _PARTITIONTIME = (SELECT MAX(_PARTITIONTIME) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}`))
  OR
  (SELECT MAX(timestamp) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}` WHERE _PARTITIONTIME = (SELECT MAX(_PARTITIONTIME) FROM `${var.project_id}.${var.dataset_id}.${var.ingestion_table_id}`)) IS NULL;
SQL
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.ingestion_dataset.dataset_id
      table_id   = "${var.continuous_query_job_prefix}output" # This is a dummy table, not actually used by continuous query with EXPORT DATA
    }
    create_disposition = "CREATE_IF_NEEDED"
    write_disposition  = "WRITE_APPEND" # Not strictly necessary for continuous export but good practice
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.ingestion_table,
    google_pubsub_topic.continuous_query_topic,
    google_service_account.continuous_query_sa,
    google_project_iam_member.bq_table_reader,
    google_project_iam_member.bq_table_user,
    google_pubsub_topic_iam_member.pubsub_publisher,
    google_project_iam_member.bq_job_user
  ]
}
