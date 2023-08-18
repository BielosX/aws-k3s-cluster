#!/bin/bash

LOCK_TABLE="${lock_table}"
LOCK_TABLE_KEY="${lock_table_key}"

function acquire_lock() {
  echo "Trying to acquire lock"
  exit_code=255
  timestamp=$(date +%s)
  while [ $exit_code -ne 0 ]; do
    output=$(aws dynamodb put-item \
      --table-name "$LOCK_TABLE" \
      --item "{\"lockID\": {\"S\": \"$LOCK_TABLE_KEY\"}, \"timestamp\": {\"N\": \"$timestamp\"}}" \
      --condition-expression "attribute_not_exists(lockID)" 2>&1)
    exit_code=$?
    echo "$output"
    sleep 5
    timestamp=$(date +%s)
  done
  echo "Lock acquired"
}

function release_lock() {
  echo "Releasing lock"
  aws dynamodb delete-item \
    --table-name "$LOCK_TABLE" \
    --key "{\"lockID\": {\"S\": \"$LOCK_TABLE_KEY\"}}"
  echo "Lock released"
}

function configure_ecr() {
  accountId="$1"
  region="$2"
  registry="$accountId.dkr.ecr.$region.amazonaws.com"
  echo "Adding image registry $registry"
  token=$(aws ecr get-login-password)
  mkdir -p /etc/rancher/k3s
cat <<EOF > /etc/rancher/k3s/registries.yaml
mirrors:
  ecr:
    endpoint:
      - "https://$registry"
configs:
  "$registry":
    auth:
      username: AWS
      password: $token
    tls:
      insecure_skip_verify: true
EOF

}

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
URL="http://169.254.169.254/latest/dynamic/instance-identity/document"
INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v "$URL")
ACCOUNT_ID=$(jq -r '.accountId' <<< "$INSTANCE_IDENTITY")
REGION=$(jq -r '.region' <<< "$INSTANCE_IDENTITY")

acquire_lock
configure_ecr "$ACCOUNT_ID" "$REGION"
release_lock