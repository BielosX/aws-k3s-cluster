#!/bin/bash

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
  echo "Install K3S"
  yum -y install container-selinux
  yum -y install https://github.com/k3s-io/k3s-selinux/releases/download/v1.4.stable.1/k3s-selinux-1.4-1.el8.noarch.rpm
  token=$(aws ssm get-parameter --name "/control-plane/token" --with-decryption |
    jq -r '.Parameter.Value')
  curl -sfL https://get.k3s.io | K3S_TOKEN="$token" sh -s - agent --server https://lb.plane.local:6443
  echo "Agent initiated"