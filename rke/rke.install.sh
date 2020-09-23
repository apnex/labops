#!/bin/bash

echo "### create rke service account ###"
sleep 1
useradd -m -g docker rke
mkdir -p /home/rke/.ssh
chmod 700 /home/rke/.ssh
chmod -R go= /home/rke/.ssh

echo "### create and copy ssh keys for rke user ###"
sleep 1
cat /dev/zero | ssh-keygen -q -N "" >/dev/null
yes | \cp ~/.ssh/id_rsa.pub /home/rke/.ssh/authorized_keys
chown -R rke:docker /home/rke
ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" rke@localhost << EOT
	docker version
EOT

echo "### install rke cli ###"
sleep 1
curl -Lo /usr/local/bin/rke https://github.com/rancher/rke/releases/download/v1.2.0-rc10/rke_linux-amd64
chmod +x /usr/local/bin/rke
rke --version

echo "### install kubectl cli ###"
sleep 1
KUBERELEASE=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
curl -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBERELEASE}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client

echo "### initialise rke cluster ###"
sleep 1
cat << EOF > ./rke.config.yaml
nodes:
  - address: localhost
    user: rke
    role:
      - controlplane
      - etcd
      - worker
ingress:
  provider: none
monitoring:
  provider: none
network:
  plugin: calico
EOF
rke up --config ./rke.config.yaml

echo "### sync kubeconfig ###"
sleep 1
mkdir -p $HOME/.kube
cp kube_config_rke.config.yaml ~/.kube/config
