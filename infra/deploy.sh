#!/bin/bash

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

terraform apply 

if [ $? -ne 0 ]; then
  echo "Error: Terraform apply failed."
  exit 1
fi

echo ""
echo "Deployment completed successfully!"
echo "You can find information about the created resources in the Terraform outputs."
echo "Run 'terraform output' to see them."
