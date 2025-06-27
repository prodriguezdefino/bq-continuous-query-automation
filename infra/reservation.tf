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

resource "google_bigquery_reservation" "continuous_query_reservation" {
  project  = var.project_id
  location = "US"
  name     = "cq-res"

  slot_capacity     = 0
  ignore_idle_slots = false
  edition           = upper(var.reservation_edition)
  concurrency       = 0
  autoscale {
    max_slots = var.max_reservation_slot_capacity
  }
}

resource "google_bigquery_reservation_assignment" "continuous_slots_assignment" {
  project     = var.project_id
  location    = google_bigquery_reservation.continuous_query_reservation.location
  assignee    = "projects/${var.project_id}"
  job_type    = "CONTINUOUS"
  reservation = google_bigquery_reservation.continuous_query_reservation.id
}
