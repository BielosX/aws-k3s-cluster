#!/bin/bash

export AWS_REGION="eu-west-1"
export AWS_PAGER=""
BACKEND_STACK_NAME="terraform-backend"

function deploy_backend() {
  pushd live || exit
  aws cloudformation deploy --template-file backend.yaml \
    --stack-name "$BACKEND_STACK_NAME" || exit
  popd || exit
}

function get_exports() {
  exports=$(aws cloudformation list-exports | jq -r '.Exports')
}

function get_backend_bucket() {
  backend_bucket_name=$(jq -r 'map(select(.Name == "TerraformStateBucketName")) | .[0].Value' <<< "$1")
  echo "Backend bucket: ${backend_bucket_name}"
}

function get_lock_table() {
  lock_table_name=$(jq -r 'map(select(.Name == "TerraformLockTableName")) | .[0].Value' <<< "$1")
  echo "Lock table name: ${lock_table_name}"
}

function deploy_vpc() {
  pushd live/vpc || exit
  get_exports
  get_backend_bucket "$exports"
  get_lock_table "$exports"
  terraform init -backend-config="bucket=$backend_bucket_name" \
    -backend-config="dynamodb_table=$lock_table_name" || exit
  terraform apply -auto-approve || exit
  popd || exit
}

function deploy_control_plane() {
  pushd live/control-plane || exit
  get_exports
  get_backend_bucket "$exports"
  get_lock_table "$exports"
  terraform init -backend-config="bucket=$backend_bucket_name" \
    -backend-config="dynamodb_table=$lock_table_name" || exit
  terraform apply -auto-approve \
    -var "vpc-state-bucket=$backend_bucket_name" || exit
  popd || exit
}

function deploy_bastion() {
  pushd live/bastion || exit
  get_exports
  get_backend_bucket "$exports"
  get_lock_table "$exports"
  terraform init -backend-config="bucket=$backend_bucket_name" \
    -backend-config="dynamodb_table=$lock_table_name" || exit
  terraform apply -auto-approve -var "vpc-state-bucket=$backend_bucket_name" || exit
  popd || exit
}

function deploy_nodes() {
  pushd live/nodes || exit
  get_exports
  get_backend_bucket "$exports"
  get_lock_table "$exports"
  terraform init -backend-config="bucket=$backend_bucket_name" \
    -backend-config="dynamodb_table=$lock_table_name" || exit
  terraform apply -auto-approve -var "vpc-state-bucket=$backend_bucket_name" \
    -var "control-plane-state-bucket=$backend_bucket_name" || exit
  popd || exit
}

function wait_for_control_plane() {
  namespace_id=$(aws servicediscovery list-namespaces \
    --filters "Name=NAME,Values=plane.local,Condition=EQ" \
    | jq -r '.Namespaces[0].Id')
  service_id=$(aws servicediscovery list-services \
    --filters "Name=NAMESPACE_ID,Values=$namespace_id,Condition=EQ" \
    | jq -r '.Services[] | select(.Name=="nodes") | .Id')
  instances=0
  while [ "$instances" -ne 3 ]; do
    echo "Number of registered control-plane instances: $instances"
    instances=$(aws servicediscovery list-instances --service-id "$service_id" | jq -r '.Instances | length')
    sleep 5
  done
}

function deploy() {
  deploy_backend
  deploy_vpc
  deploy_bastion
  deploy_control_plane
  wait_for_control_plane
  deploy_nodes
}

function destroy_vpc() {
  pushd live/vpc || exit
  terraform destroy -auto-approve || exit
  popd || exit
}

function destroy_control_plane() {
  pushd live/control-plane || exit
  get_exports
  get_backend_bucket "$exports"
  terraform destroy -auto-approve \
    -var "vpc-state-bucket=$backend_bucket_name" || exit
  popd || exit
}

function destroy_bastion() {
  pushd live/bastion || exit
  get_exports
  get_backend_bucket "$exports"
  terraform destroy -auto-approve -var "vpc-state-bucket=$backend_bucket_name" || exit
  popd || exit
}

function destroy_nodes() {
  pushd live/nodes || exit
  get_exports
  get_backend_bucket "$exports"
  terraform destroy -auto-approve \
    -var "vpc-state-bucket=$backend_bucket_name" \
    -var "control-plane-state-bucket=$backend_bucket_name"|| exit
  popd || exit
}

function clean_bucket() {
  bucket="$1"
  echo "Cleaning bucket: ${bucket}"
  versions=$(aws s3api list-object-versions \
    --bucket "$bucket" \
    --output=json \
    --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')
  aws s3api delete-objects --bucket "$bucket" --delete "$versions"
}

function destroy_backend() {
  pushd live || exit
  get_exports
  get_backend_bucket "$exports"
  clean_bucket "$backend_bucket_name"
  aws cloudformation delete-stack \
    --stack-name "$BACKEND_STACK_NAME" || exit
  aws cloudformation wait stack-delete-complete \
    --stack-name "$BACKEND_STACK_NAME" || exit
  popd || exit
}

function destroy() {
  destroy_nodes
  destroy_control_plane
  destroy_bastion
  destroy_vpc
  destroy_backend
  aws ssm delete-parameters --names "/control-plane/token"
  aws ssm delete-parameters --names "/control-plane/kubeconfig"
}

case "$1" in
  "deploy") deploy ;;
  "destroy") destroy ;;
esac