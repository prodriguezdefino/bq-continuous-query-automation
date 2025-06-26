#!/bin/bash

# Get current gcloud project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)

if [ -z "$CURRENT_PROJECT" ]; then
  echo "No active GCP project found in gcloud configuration."
  read -p "Please enter your Google Cloud Project ID: " TF_VAR_project_id
else
  read -p "Using GCP project '$CURRENT_PROJECT'. Press Enter to confirm or enter a different Project ID: " INPUT_PROJECT_ID
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

echo "Using Project ID: $TF_VAR_project_id"
echo ""

# Initialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade # -upgrade can help with provider version issues
if [ $? -ne 0 ]; then
  echo "Error: Terraform initialization failed."
  exit 1
fi

echo ""
echo "Applying Terraform configuration..."
echo "You will be prompted to confirm the changes by Terraform."
echo ""

terraform apply -var="project_id=$TF_VAR_project_id"

if [ $? -ne 0 ]; then
  echo "Error: Terraform apply failed."
  exit 1
fi

echo ""
echo "Deployment completed successfully!"
echo "You can find information about the created resources in the Terraform outputs."
echo "Run 'terraform output' to see them."
