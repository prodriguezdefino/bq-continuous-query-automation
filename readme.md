# BigQuery Continuous Query Recovery Automation

## Overview

This project demonstrates an automated system for detecting and restarting failed BigQuery continuous queries. When a continuous query job is unexpectedly cancelled or encounters an error that halts its operation, this automation ensures that the query is restarted from the point of failure, minimizing data loss and manual intervention. This project is intended for demonstration purposes only. It is not intended to be used in a production environment directly.

## How it Works

The system leverages several Google Cloud services:

1.  **BigQuery Continuous Query:** A primary continuous query is set up to process data from an `ingestion_table`. This query exports its results to a Google Cloud Pub/Sub topic.
2.  **Cloud Logging & Pub/Sub:** A log sink is configured in Cloud Logging to capture BigQuery job completion events. These logs, specifically those indicating a failed or cancelled continuous query, are published to a dedicated Pub/Sub topic.
3.  **Cloud Function:** A Python-based Cloud Function is subscribed to this Pub/Sub topic. When a relevant log message is received, the function is triggered.
4.  **Automated Restart Logic:**
    *   The Cloud Function parses the log entry to identify the failed job's details, including its original query and the timestamp when it stopped.
    *   It checks if the job ID matches a predefined prefix for the continuous queries managed by this system.
    *   If the job was indeed cancelled (and not intentionally stopped by a user), the function modifies the original SQL query. It updates the start timestamp in the query to the end time of the failed job, ensuring that data processing resumes from where it left off.
    *   A new BigQuery continuous query job is then initiated with this modified query and a new unique job ID.

This closed-loop system provides resilience to your BigQuery continuous queries.

## Prerequisites

Before deploying this solution, ensure you have the following:

*   **Google Cloud SDK (`gcloud`):** Installed and configured with credentials.
*   **Terraform:** Installed (see `infra/main.tf` for version requirements).
*   **Permissions:** Your Google Cloud user or service account must have sufficient permissions to:
    *   Create and manage Google Cloud projects (or have an existing project).
    *   Enable necessary APIs (BigQuery, Pub/Sub, Cloud Functions, Cloud Logging, IAM, Service Usage, Cloud Resource Manager).
    *   Create and manage Service Accounts and IAM policies.
    *   Create and manage BigQuery datasets, tables, and jobs.
    *   Create and manage Pub/Sub topics and subscriptions.
    *   Create and manage Cloud Functions and related storage.
    *   Create and manage Cloud Logging sinks.
    *   Create and manage BigQuery Reservations and Assignments.

## Setup

1.  **Clone the Repository:**

2.  **Configure Terraform Variables:**
    *   Copy the example variables file:
        ```bash
        cp infra/terraform.tfvars.example infra/terraform.tfvars
        ```
    *   Edit `infra/terraform.tfvars` and provide your Google Cloud `project_id`. You can also customize other variables like `region`, `dataset_id`, etc., if needed.

3.  **Deploy Infrastructure:**
    *   The `setup.sh` script runs `terraform apply` to create all the necessary Google Cloud resources defined in the Terraform configuration.
    *   Navigate to the `infra` directory and run the deployment script:
        ```bash
        ./setup.sh
        ```
    *   Review the plan and type `yes` when prompted by Terraform.

## Usage / Demonstration

1.  **Ingest Data:**
    *   Once deployed, the BigQuery table specified by `dataset_id` and `ingestion_table_id` (default: `continuous_ingestion_dataset.ingestion_table`) is ready to receive data.
    *   You can manually insert data into this table using the BigQuery console or `bq` command-line tool. For example:
        ```sql
        INSERT INTO your_project_id.continuous_ingestion_dataset.ingestion_table (message, timestamp)
        VALUES ('hello world', CURRENT_TIMESTAMP());
        ```
    *   The continuous query defined in `infra/bigquery.tf` will process new data from this table.

2.  **View Output:**
    *   The continuous query is configured to export data to the Pub/Sub topic specified by `pubsub_topic_id` (default: `continuous_query_topic`).
    *   You can create a subscription to this topic in the Google Cloud Console or using `gcloud` to view the messages processed by the continuous query.

3.  **Generate a cancellation and observe no action:**
    *   **Identify the Continuous Query Job:** Go to the BigQuery console in your project. Under "Query history" or "Job history," find the active continuous query job. Its ID will typically start with the `continuous_query_job_prefix` (default: `continuous_query_`).
    *   **Manually Cancel the Job:** Select the job and cancel it.
    *   **Observe Logs:**
        *   Navigate to Cloud Logging and search for logs related to BigQuery job completions.
        *   You should see a log entry indicating the job was cancelled.
        *   This log entry will not trigger the `query_restarter_function` Cloud Function (given that this is a user driven action).


## Cleanup

To remove all resources created by this project and avoid ongoing charges:

1.  **Destroy Infrastructure:**
    *   Run the cleanup script:
        ```bash
        ./cleanup.sh
        ```
    *   This will execute `terraform destroy`. Review the resources to be deleted and type `yes` when prompted.

This ensures all components of the automation are removed from your project.
