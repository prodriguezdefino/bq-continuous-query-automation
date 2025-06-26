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

variable "project_id" {
  description = "The ID of the Google Cloud project."
  type        = string
}

variable "region" {
  description = "The region for Google Cloud resources."
  type        = string
  default     = "us-central1"
}

variable "dataset_id" {
  description = "The ID of the BigQuery dataset."
  type        = string
  default     = "continuous_ingestion_dataset"
}

variable "ingestion_table_id" {
  description = "The ID of the BigQuery ingestion table."
  type        = string
  default     = "ingestion_table"
}

variable "pubsub_topic_id" {
  description = "The ID of the Pub/Sub topic."
  type        = string
  default     = "continuous_query_topic"
}

variable "service_account_id" {
  description = "The ID of the service account for the continuous query."
  type        = string
  default     = "bq-continuous-query-sa"
}

variable "cloud_function_name" {
  description = "The name of the Cloud Function to handle log entries."
  type        = string
  default     = "bq_continuous_query_restarter"
}

variable "continuous_query_job_prefix" {
  description = "The prefix for the continuous query job ID."
  type        = string
  default     = "continuous_query_"
}
