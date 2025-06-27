#!/bin/bash

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

terraform destroy

if [ $? -ne 0 ]; then
  echo "Error: Terraform destroy failed. Some resources may still exist."
  exit 1
fi

echo ""
echo "Cleanup completed successfully!"
