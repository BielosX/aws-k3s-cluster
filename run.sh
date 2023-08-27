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

function deploy_ecr() {
  pushd live/ecr || exit
  get_exports
  get_backend_bucket "$exports"
  get_lock_table "$exports"
  terraform init -backend-config="bucket=$backend_bucket_name" \
    -backend-config="dynamodb_table=$lock_table_name" || exit
  terraform apply -auto-approve || exit
  popd || exit
}

function deploy_node_manager() {
  tag=$(date +%s)
  pushd node-manager || exit
  ./gradlew clean build spotlessJavaCheck dockerBuildImage -DimageTag="$tag" || exit
  popd || exit
  pushd live/ecr || exit
  node_manager_repository_url=$(terraform output -raw "node-manager-repository-url")
  popd || exit
  account_id=$(aws sts get-caller-identity | jq -r '.Account')
  aws ecr get-login-password \
    | docker login --username AWS --password-stdin "${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  new_tag="${node_manager_repository_url}:${tag}"
  docker tag "node-manager:${tag}" "$new_tag"
  docker push "$new_tag"
}

function get_latest_node_manager() {
  account_id=$(aws sts get-caller-identity | jq -r '.Account')
  latest_tag=$(aws ecr list-images --repository-name "node-manager" \
    | jq -r '.imageIds | map(.imageTag | tonumber) | max')
  latest_node_manager="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com/node-manager:${latest_tag}"
}

function deploy_control_plane() {
  pushd iam-provider-lambda || exit
  ./gradlew clean build shadowJar spotlessJavaCheck
  jar_path=$(readlink -f build/libs/iam-provider-lambda-all.jar)
  popd || exit
  pushd live/control-plane || exit
  get_exports
  get_backend_bucket "$exports"
  get_lock_table "$exports"
  get_latest_node_manager
  echo "Latest node-manager: $latest_node_manager"
  terraform init -backend-config="bucket=$backend_bucket_name" \
    -backend-config="dynamodb_table=$lock_table_name" || exit
  terraform apply -auto-approve \
    -var "vpc-state-bucket=$backend_bucket_name" \
    -var "node-manager-image=$latest_node_manager" \
    -var "iam-role-provider-lambda-jar=$jar_path" || exit
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
  deploy_ecr
  deploy_node_manager
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

function destroy_ecr() {
  pushd live/ecr || exit
  terraform destroy -auto-approve || exit
  popd || exit
}

function destroy_control_plane() {
  pushd live/control-plane || exit
  get_exports
  get_backend_bucket "$exports"
  temp_file=$(mktemp)
  terraform destroy -auto-approve \
    -var "vpc-state-bucket=$backend_bucket_name" \
    -var "node-manager-image=temp" \
    -var "iam-role-provider-lambda-jar=$temp_file"|| exit
  rm "$temp_file"
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
  destroy_ecr
  destroy_backend
  aws ssm delete-parameters --names "/control-plane/token"
  aws ssm delete-parameters --names "/control-plane/kubeconfig"
}

function tunnel_control_plane() {
  bastion_id=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=bastion-host" "Name=instance-state-name,Values=running" \
    | jq -r '.Reservations[0].Instances[0].InstanceId')
  aws ssm start-session \
      --target "$bastion_id" \
      --document-name AWS-StartPortForwardingSessionToRemoteHost \
      --parameters '{"host":["nodes.plane.local"],"portNumber":["6443"], "localPortNumber":["6443"]}'
}

function local_kubeconfig() {
  param=$(aws ssm get-parameter --name "/control-plane/kubeconfig" --with-decryption | jq -r '.Parameter.Value')
  mkdir -p ~/.kube
  echo "${param//nodes.plane.local/localhost}" > ~/.kube/config
}

case "$1" in
  "deploy") deploy ;;
  "destroy") destroy ;;
  "tunnel-cp") tunnel_control_plane ;;
  "local-kubeconfig") local_kubeconfig ;;
esac