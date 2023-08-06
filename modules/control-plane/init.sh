#!/bin/bash -xe
LOCK_TABLE="${lock_table}"
SERVICE_ID="${service_id}"
export AWS_PAGER=""

function acquire_lock() {
  echo "Trying to acquire lock"
  exit_code=255
  while [ $exit_code -ne 0 ]; do
    sleep 5
    message=$(aws dynamodb put-item \
      --table-name "$LOCK_TABLE" \
      --item '{"lockID": {"S": "control-plane"}}' \
      --condition-expression "attribute_not_exists(lockID)")
    exit_code=$?
    echo "$message"
  done
  echo "Lock acquired"
}

function release_lock() {
  echo "Releasing lock"
  aws dynamodb delete-item \
    --table-name "$LOCK_TABLE" \
    --key '{"lockID": {"S": "control-plane"}}'
  echo "Lock released"
}

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
  echo "Install K3S"
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  URL="http://169.254.169.254/latest/dynamic/instance-identity/document"
  INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v "$URL")
  INSTANCE_ID=$(jq -r '.instanceId' <<< "$INSTANCE_IDENTITY")
  PRIVATE_IP=$(jq -r '.privateIp' <<< "$INSTANCE_IDENTITY")
  acquire_lock
  aws servicediscovery register-instance \
    --service-id "$SERVICE_ID" \
    --instance-id "$INSTANCE_ID" \
    --attributes "{\"AWS_INSTANCE_IPV4\": \"$PRIVATE_IP\"}"
  release_lock