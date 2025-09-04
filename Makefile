AWS_REGION ?= us-east-1
ENV ?= dev

.PHONY: bootstrap init plan apply build-api pack-api

bootstrap:
	terraform -chdir=iac/bootstrap init
	terraform -chdir=iac/bootstrap apply -auto-approve -var="region=$(AWS_REGION)" -var="env=$(ENV)"

init:
	terraform -chdir=iac init

plan:
	terraform -chdir=iac plan -var="region=$(AWS_REGION)" -var="env=$(ENV)" -var="account_id=$(ACCOUNT_ID)"

apply:
	terraform -chdir=iac apply -auto-approve -var="region=$(AWS_REGION)" -var="env=$(ENV)" -var="account_id=$(ACCOUNT_ID)"

build-api:
	cd services/api && (test -f package-lock.json && npm ci || npm install) && npm run build

pack-api:
	cd services/api && (test -f package-lock.json && npm ci || npm install) && npm run pack
