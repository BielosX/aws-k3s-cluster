#!/bin/bash

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

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
  echo "Install K3S"
  yum -y install container-selinux
  yum -y install https://github.com/k3s-io/k3s-selinux/releases/download/v1.4.stable.1/k3s-selinux-1.4-1.el8.noarch.rpm
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  URL="http://169.254.169.254/latest/dynamic/instance-identity/document"
  INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v "$URL")
  INSTANCE_ID=$(jq -r '.instanceId' <<< "$INSTANCE_IDENTITY")
  ACCOUNT_ID=$(jq -r '.accountId' <<< "$INSTANCE_IDENTITY")
  REGION=$(jq -r '.region' <<< "$INSTANCE_IDENTITY")
  mkdir -p /etc/sysctl.d
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/99-ip-forward.conf
  sysctl --system
  configure_ecr "$ACCOUNT_ID" "$REGION"
  token=$(aws ssm get-parameter --name "/control-plane/token" --with-decryption |
    jq -r '.Parameter.Value')
  curl -sfL https://get.k3s.io | K3S_TOKEN="$token" sh -s - agent \
    --server https://nodes.plane.local:6443 \
    --node-label "aws/instance-id=$INSTANCE_ID"
  echo "Agent initiated"