#!/usr/bin/env python
#
# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import base64
import json
import os
from google.cloud import bigquery

def restart_bq_job(event, context):
    """
    Cloud Function to restart a BigQuery job if it's found to be cancelled.
    Triggered by a Pub/Sub message from a log sink.
    """
    log_entry_data = base64.b64decode(event['data']).decode('utf-8')
    log_entry = json.loads(log_entry_data)

    print(f"Received log entry: {log_entry}")

    project_id = os.environ.get('GCP_PROJECT')
    bq_job_prefix = os.environ.get('BQ_JOB_PREFIX', 'continuous_query_') # Default if not set

    if 'protoPayload' in log_entry and \
       'methodName' in log_entry['protoPayload'] and \
       log_entry['protoPayload']['methodName'] == 'jobservice.jobcompleted' and \
       'serviceData' in log_entry['protoPayload'] and \
       'jobCompletedEvent' in log_entry['protoPayload']['serviceData'] and \
       'job' in log_entry['protoPayload']['serviceData']['jobCompletedEvent'] and \
       'jobStatus' in log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job'] and \
       'error' in log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobStatus'] and \
       'jobConfiguration' in log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job'] and \
       'query' in log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobConfiguration'] and \
       'queryDestinationTable' in log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobConfiguration']['query']:

        job_status = log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobStatus']
        job_id = log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobName']['jobId']
        job_config = log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobConfiguration']['query']

        # Check if the job ID matches our continuous query prefix
        if not job_id.startswith(bq_job_prefix):
            print(f"Job ID {job_id} does not match prefix {bq_job_prefix}. Ignoring.")
            return

        # Check for cancellation error
        # Specific error messages for cancellation can vary. This is a general check.
        # You might need to refine this based on exact log messages.
        is_cancelled = False
        if job_status['error'].get('message') and 'cancelled' in job_status['error']['message'].lower():
            is_cancelled = True
        # BigQuery internal errors sometimes use "STOPPED" for continuous queries that are effectively cancelled by the system
        elif job_status.get('state') == 'DONE' and job_status['error'].get('reason') == 'stopped':
             is_cancelled = True


        if is_cancelled:
            print(f"Detected cancelled BigQuery job: {job_id}. Attempting to restart.")

            client = bigquery.Client(project=project_id)
            
            original_query = job_config['query']
            destination_table_ref_proto = job_config['queryDestinationTable']
            destination_dataset_id = destination_table_ref_proto['datasetId']
            destination_table_id = destination_table_ref_proto['tableId']
            
            # Construct the job configuration for restart
            # We reuse the original query and its settings.
            # The continuous query name is embedded in the DDL.
            
            job_config_restart = bigquery.QueryJobConfig(
                create_disposition=job_config.get('createDisposition', 'CREATE_IF_NEEDED'),
                write_disposition=job_config.get('writeDisposition', 'WRITE_APPEND'),
                use_legacy_sql=job_config.get('useLegacySql', False),
                # Ensure the destination is set, even if it's a dummy for EXPORT DATA
                destination=client.dataset(destination_dataset_id, project=project_id).table(destination_table_id)
            )

            try:
                # For continuous queries, we re-run the CREATE OR REPLACE CONTINUOUS QUERY statement
                query_job = client.query(original_query, job_config=job_config_restart, job_id_prefix=bq_job_prefix)
                print(f"Restarted BigQuery job with new job ID: {query_job.job_id}. Query: \n{original_query}")
                # Wait for the job to complete (optional, good for debugging)
                # query_job.result() 
                # print(f"Restart job {query_job.job_id} completed with state: {query_job.state}")

            except Exception as e:
                print(f"Error restarting BigQuery job {job_id}: {e}")
        else:
            print(f"Job {job_id} completed with status: {job_status['error'] if 'error' in job_status else 'successful'}. No action needed.")
    else:
        print("Log entry does not match expected structure for a BigQuery job completion event or is not an error.")

    return 'OK'
