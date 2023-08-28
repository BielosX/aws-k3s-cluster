#!/bin/bash
LOCK_TABLE="${lock_table}"
SERVICE_ID="${service_id}"
POD_CIDR="${kubernetes_pod_cidr}"
SERVICE_CIDR="${kubernetes_service_cidr}"
CLUSTER_DNS="${kubernetes_cluster_dns}"
NODE_MANAGER_IMAGE="${node_manager_image}"
WEBHOOK_URL="${webhook_url}"
WEBHOOK_TOKEN_PARAM="${webhook_token_param}"

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

# https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers
function setup_webhook() {
  export LAMBDA_URL="$WEBHOOK_URL"
  envsubst < /opt/webhook.yaml | KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f -
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

function setup_webhook_config() {
  echo "Fetching webhook token from SSM param $WEBHOOK_TOKEN_PARAM"
  token=$(aws ssm get-parameter --with-decryption --name "$WEBHOOK_TOKEN_PARAM" \
    | jq -r '.Parameter.Value')
  export WEBHOOK_TOKEN="$token"
  envsubst < /opt/webhook-config.yaml > /opt/webhook-config-user-password.yaml
}

function create_server_node() {
  instance_id="$1"
  node_ip="$2"
  node_label="aws/instance-id=$instance_id"
  taint="node-role.kubernetes.io/control-plane:NoSchedule"
  domain="nodes.plane.local"
  api_server_admission_config="--admission-control-config-file=/opt/admission-config.yaml"
  api_server_admission_enable="--enable-admission-plugins=MutatingAdmissionWebhook"
  parameters=$(aws ssm get-parameters --names "/control-plane/token" \
    --with-decryption)
  length=$(jq -r '.Parameters | length' <<< "$parameters")
  if [ "$length" -eq 0 ]; then
    echo "Token not fount, starting as first node"
    curl -sfL https://get.k3s.io | sh -s - server \
      --cluster-init \
      --tls-san "$domain" \
      --node-label "$node_label" \
      --node-taint "$taint" \
      --cluster-cidr "$POD_CIDR" \
      --service-cidr "$SERVICE_CIDR" \
      --cluster-dns "$CLUSTER_DNS" \
      --node-ip "$node_ip" \
      --prefer-bundled-bin \
      --selinux \
      --kube-apiserver-arg="$api_server_admission_config" \
      --kube-apiserver-arg="$api_server_admission_enable"
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
    echo "Setup webhook"
    setup_webhook
    echo "FIRST CP INITIALIZED"
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
      --cluster-cidr "$POD_CIDR" \
      --service-cidr "$SERVICE_CIDR" \
      --cluster-dns "$CLUSTER_DNS" \
      --node-ip "$node_ip" \
      --prefer-bundled-bin \
      --selinux \
      --kube-apiserver-arg="$api_server_admission_config" \
      --kube-apiserver-arg="$api_server_admission_enable"
  fi
}

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
  echo "Install K3S"
  yum -y install container-selinux
  yum -y install https://github.com/k3s-io/k3s-selinux/releases/download/v1.4.stable.1/k3s-selinux-1.4-1.el8.noarch.rpm
  yum -y install cronie
  systemctl enable cronie.service
  systemctl start cronie.service
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  URL="http://169.254.169.254/latest/dynamic/instance-identity/document"
  INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v "$URL")
  INSTANCE_ID=$(jq -r '.instanceId' <<< "$INSTANCE_IDENTITY")
  PRIVATE_IP=$(jq -r '.privateIp' <<< "$INSTANCE_IDENTITY")
  ACCOUNT_ID=$(jq -r '.accountId' <<< "$INSTANCE_IDENTITY")
  REGION=$(jq -r '.region' <<< "$INSTANCE_IDENTITY")
  mkdir -p /etc/sysctl.d
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/99-ip-forward.conf
  echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/99-bridge-iptables.conf
  sysctl --system
  setup_webhook_config
  configure_ecr "$ACCOUNT_ID" "$REGION"
  setup_node_manager_pod
  acquire_lock
  create_server_node "$INSTANCE_ID" "$PRIVATE_IP"
  aws servicediscovery register-instance \
    --service-id "$SERVICE_ID" \
    --instance-id "$INSTANCE_ID" \
    --attributes "{\"AWS_INSTANCE_IPV4\": \"$PRIVATE_IP\"}"
  release_lock