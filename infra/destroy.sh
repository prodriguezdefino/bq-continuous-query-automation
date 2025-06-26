#!/bin/bash

# Get current gcloud project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)

if [ -z "$CURRENT_PROJECT" ]; then
  echo "No active GCP project found in gcloud configuration."
  read -p "Please enter your Google Cloud Project ID (must be the one used for deployment): " TF_VAR_project_id
else
  read -p "Destroying resources in GCP project '$CURRENT_PROJECT'. Press Enter to confirm or enter the correct Project ID: " INPUT_PROJECT_ID
  if [ -z "$INPUT_PROJECT_ID" ]; then
    TF_VAR_project_id=$CURRENT_PROJECT
  else
    TF_VAR_project_id=$INPUT_PROJECT_ID
  fi
fi

if [ -z "$TF_VAR_project_id" ]; then
  echo "Error: Project ID cannot be empty."
  exit 1
fi

echo "Targeting Project ID: $TF_VAR_project_id for destruction."
echo ""
echo "WARNING: This will attempt to destroy all resources managed by this Terraform configuration in the specified project."
read -p "Are you sure you want to continue? (yes/no): " CONFIRMATION

if [[ "$CONFIRMATION" != "yes" ]]; then
  echo "Aborted by user."
  exit 0
fi

echo ""
echo "Destroying Terraform-managed resources..."
echo "You will be prompted to confirm the destruction by Terraform."
echo ""

terraform destroy -var="project_id=$TF_VAR_project_id"

if [ $? -ne 0 ]; then
  echo "Error: Terraform destroy failed. Some resources may still exist."
  exit 1
fi

echo ""
echo "Cleanup completed successfully!"
