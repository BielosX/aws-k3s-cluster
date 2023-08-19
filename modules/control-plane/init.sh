#!/bin/bash
LOCK_TABLE="${lock_table}"
SERVICE_ID="${service_id}"
POD_CIDR="${kubernetes_pod_cidr}"
SERVICE_CIDR="${kubernetes_service_cidr}"
NODE_MANAGER_IMAGE="${node_manager_image}"

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

function setup_node_manager_pod() {
  mkdir -p /var/lib/rancher/k3s/agent/pod-manifests/
cat <<EOF > /var/lib/rancher/k3s/agent/pod-manifests/node-manager.yaml
apiVersion: v1
kind: Pod
metadata:
  name: node-manager
  namespace: kube-system
spec:
  containers:
    - name: node-manager
      image: "$NODE_MANAGER_IMAGE"
      env:
        - name: "SERVICE_ID"
          value: "$SERVICE_ID"
        - name: "LOCK_TABLE"
          value: "$LOCK_TABLE"
EOF
}

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
  instance_id="$1"
  node_label="aws/instance-id=$instance_id"
  taint="node-role.kubernetes.io/control-plane:NoSchedule"
  domain="nodes.plane.local"
  parameters=$(aws ssm get-parameters --names "/control-plane/token" \
    --with-decryption)
  length=$(jq -r '.Parameters | length' <<< "$parameters")
  if [ "$length" -eq 0 ]; then
    echo "Token not fount, starting as first node"
    curl -sfL https://get.k3s.io | sh -s - server \
      --cluster-init --tls-san "$domain" \
      --node-label "$node_label" --node-taint "$taint" \
      --cluster-cidr "$POD_CIDR" --service-cidr "$SERVICE_CIDR"
    token=$(cat /var/lib/rancher/k3s/server/node-token)
    aws ssm put-parameter --name "/control-plane/token" \
      --value "$token" \
      --type "SecureString"
    tmp_file=$(mktemp)
    sed 's/127.0.0.1/nodes.plane.local/g' /etc/rancher/k3s/k3s.yaml > "$tmp_file"
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
      --tls-san "$domain" \
      --node-label "$node_label" \
      --node-taint "$taint" \
      --cluster-cidr "$POD_CIDR" --service-cidr "$SERVICE_CIDR"
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
  ACCOUNT_ID=$(jq -r '.accountId' <<< "$INSTANCE_IDENTITY")
  REGION=$(jq -r '.region' <<< "$INSTANCE_IDENTITY")
  configure_ecr "$ACCOUNT_ID" "$REGION"
  setup_node_manager_pod
  acquire_lock
  create_server_node "$INSTANCE_ID"
  aws servicediscovery register-instance \
    --service-id "$SERVICE_ID" \
    --instance-id "$INSTANCE_ID" \
    --attributes "{\"AWS_INSTANCE_IPV4\": \"$PRIVATE_IP\"}"
  release_lock