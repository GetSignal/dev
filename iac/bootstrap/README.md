Bootstrap steps for Terraform remote state (run once per account/env).

1) Initialize and apply bootstrap:
   - `terraform -chdir=iac/bootstrap init`
   - `terraform -chdir=iac/bootstrap apply -var="region=us-east-1" -var="env=dev"`

2) Copy the output bucket and table names into `iac/backend.tf` backend block.

3) Then run main IaC:
   - `terraform -chdir=iac init`
   - `terraform -chdir=iac apply -var="region=us-east-1" -var="env=dev" -var="account_id=856558476421"`

