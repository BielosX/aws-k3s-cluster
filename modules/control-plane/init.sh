#!/bin/bash
LOCK_TABLE="${lock_table}"
SERVICE_ID="${service_id}"

function acquire_lock() {
  echo "Trying to acquire lock"
  exit_code=255
  timestamp=$(date +%s)
  while [ $exit_code -ne 0 ]; do
    output=$(aws dynamodb put-item \
      --table-name "$LOCK_TABLE" \
      --item "{\"lockID\": {\"S\": \"control-plane\"}, \"timestamp\": {\"N\": \"$timestamp\"}}" \
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
    --key '{"lockID": {"S": "control-plane"}}'
  echo "Lock released"
}

function create_server_node() {
  parameters=$(aws ssm get-parameters --names "/control-plane/token" \
    --with-decryption)
  length=$(jq -r '.Parameters | length' <<< "$parameters")
  if [ "$length" -eq 0 ]; then
    echo "Token not fount, starting as first node"
    curl -sfL https://get.k3s.io | sh -s - server --cluster-init --tls-san "lb.plane.local"
    token=$(cat /var/lib/rancher/k3s/server/node-token)
    aws ssm put-parameter --name "/control-plane/token" \
      --value "$token" \
      --type "SecureString"
    tmp_file=$(mktemp)
    sed 's/127.0.0.1/lb.plane.local/g' /etc/rancher/k3s/k3s.yaml > "$tmp_file"
    kubeconfig=$(cat "$tmp_file")
    rm "$tmp_file"
    aws ssm put-parameter --name "/control-plane/kubeconfig" \
      --value "$kubeconfig" \
      --type "SecureString"
    echo "Token stored in SSM as /control-plane/token"
    echo "Kubeconfig stored in SSM as /control-plane/kubeconfig"
  else
    echo "Token found, joining control-plane"
    server_ip=$(aws servicediscovery list-instances \
      --service-id "$SERVICE_ID" | jq -r '.Instances[0].Attributes.AWS_INSTANCE_IPV4')
    token=$(aws ssm get-parameter --name "/control-plane/token" --with-decryption |
      jq -r '.Parameter.Value')
    echo "Connecting to server $server_ip"
    curl -sfL https://get.k3s.io | K3S_TOKEN="$token" sh -s - server \
      --server "https://$server_ip:6443" \
      --tls-san "lb.plane.local"
    journalctl -xeu k3s.service
  fi
}

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
  echo "Install K3S"
  yum -y install container-selinux
  yum -y install https://github.com/k3s-io/k3s-selinux/releases/download/v1.4.stable.1/k3s-selinux-1.4-1.el8.noarch.rpm
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  URL="http://169.254.169.254/latest/dynamic/instance-identity/document"
  INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v "$URL")
  INSTANCE_ID=$(jq -r '.instanceId' <<< "$INSTANCE_IDENTITY")
  PRIVATE_IP=$(jq -r '.privateIp' <<< "$INSTANCE_IDENTITY")
  acquire_lock
  create_server_node
  aws servicediscovery register-instance \
    --service-id "$SERVICE_ID" \
    --instance-id "$INSTANCE_ID" \
    --attributes "{\"AWS_INSTANCE_IPV4\": \"$PRIVATE_IP\"}"
  release_lock