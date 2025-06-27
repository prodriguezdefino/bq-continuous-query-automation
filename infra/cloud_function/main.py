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
import re
import uuid

import google.auth
import google.auth.transport.requests
import requests

def restart_bq_continuous(event, context):
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
       'query' in log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobConfiguration']:

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
        if job_status['error'].get('message') and \
            'cancelled' in job_status['error']['message'].lower() and \
                'user requested cancellation' not in job_status['error']['message'].lower():
            is_cancelled = True
        # BigQuery internal errors sometimes use "STOPPED" for continuous queries that are effectively cancelled by the system
        elif job_status.get('state') == 'DONE' and job_status['error'].get('reason') == 'stopped':
            is_cancelled = True
        # if the schema of the table has changed destructively we restart the CQ
        elif job_status.get('state') == 'DONE' and \
            'schema for table' in job_status['error']['message'].lower():
            is_cancelled = True
        # if the query plan has changed we restart as well
        elif job_status.get('state') == 'DONE' and \
            'query plan is changed' in job_status['error']['message'].lower():
            is_cancelled = True

        if is_cancelled:
            print(f"Detected cancelled BigQuery job: {job_id}. Attempting to restart.")
            
            credentials, project = google.auth.default(
                scopes=["https://www.googleapis.com/auth/cloud-platform"]
            )
            request = google.auth.transport.requests.Request()
            credentials.refresh(request)
            access_token = credentials.token

            original_query = job_config['query']
            original_start_timestamp = "CURRENT_TIMESTAMP() - INTERVAL 1 SECOND"
            end_timestamp = log_entry['protoPayload']['serviceData']['jobCompletedEvent']['job']['jobStatistics']['endTime']

            # Adjust the timestamp in the SQL query
            timestamp_match = re.search(
                r"\s*TIMESTAMP\(('.*?')\)(\s*\+ INTERVAL 1 MICROSECOND)?", original_query
            )

            if timestamp_match:
                original_timestamp = timestamp_match.group(1)
                new_timestamp = f"'{end_timestamp}'"
                new_sql_query = original_query.replace(original_timestamp, new_timestamp)
            elif original_start_timestamp in original_query:
                new_timestamp = f"TIMESTAMP('{end_timestamp}') + INTERVAL 1 MICROSECOND"
                new_sql_query = original_query.replace(original_start_timestamp, new_timestamp)

            new_job_id = bq_job_prefix + str(uuid.uuid4())[:8]   
            service_account = log_entry['protoPayload']['authenticationInfo']['principalEmail']

            url = f"https://bigquery.googleapis.com/bigquery/v2/projects/{project}/jobs"
            headers = {
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            }

            try:
                data = {
                    "configuration": {
                        "query": {
                            "query": new_sql_query,
                            "useLegacySql": False,
                            "continuous": True,
                            "connectionProperties": [
                                {"key": "service_account", "value": service_account}
                            ],
                        },
                    },
                    "jobReference": {
                        "projectId": project,
                        "jobId": new_job_id,  
                    },
                }
                response = requests.post(url, headers=headers, json=data)
                if response.status_code == 200:
                    print(f"Continuous query job successfully created with job ID {new_job_id}.")
                else:
                    print(f"Error creating new continuous query job: {response.text}")
            except Exception as e:
                print(f"Error restarting BigQuery job {job_id}: {e}")
        else:
            print(f"Job {job_id} completed with status: {job_status['error'] if 'error' in job_status else 'successful'}. No action needed.")
    else:
        print("Log entry does not match expected structure for a BigQuery job completion event or is not an error.")

    return 'OK'
