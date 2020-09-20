### base OS prep
```
yum install -y epel-release
yum install -y openssl jq open-vm-tools
```

### disable selinux
```
setenforce 0
sed -i 's/^SELINUX=[a-z]*$/SELINUX=disabled/' /etc/selinux/config
```

### disable swap
```
sed -i '/swap/d' /etc/fstab
swapoff -a
```

### load modules
```
./load.modules.sh
```

### enable ip-forward / nf-call-iptables
```
cat <<-EOF > /etc/sysctl.d/k8s.conf
	net.bridge.bridge-nf-call-ip6tables = 1
	net.bridge.bridge-nf-call-iptables = 1
	net.ipv4.ip_forward = 1
EOF
sysctl --system
sysctl net.bridge.bridge-nf-call-iptables
```

---
### setup docker repo
```
yum install -y yum-utils
yum-config-manager \
	--add-repo \
	https://download.docker.com/linux/centos/docker-ce.repo
```

### install docker
```
yum install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker
```

### install kubectl
```
KUBERELEASE=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
curl -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBERELEASE}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client
```

curl -Lo /usr/local/bin/rke https://github.com/rancher/rke/releases/download/v1.2.0-rc10/rke_linux-amd64

### install rke
```
curl -Lo /usr/local/bin/rke https://github.com/rancher/rke/releases/latest/download/rke_linux-amd64
chmod +x /usr/local/bin/rke
rke --version
```

### docker user
```
useradd -m -g docker rke
mkdir -p rke/.ssh
chmod 700 rke/.ssh
touch rke/.ssh/authorized_keys
chmod -R go= rke/.ssh
chown -R rke:docker /home/rke
```

### create and copy ssh keys to self
```
cat /dev/zero | ssh-keygen -q -N "" >/dev/null
cat ~/.ssh/id_rsa.pub | ssh root@localhost "sudo tee -a /home/rke/.ssh/authorized_keys"
ssh rke@localhost docker version
```

### clone labops
```
yum -y install git
git clone https://github.com/apnex/labops
cd labops
```

### start rke
```
rke up --config ./rke.config.yaml
```

### copy kubeconfig
```
mkdir -p $HOME/.kube
cp kube_config_rke.config.yaml ~/.kube/config
```

### install local-path-provisioner
```
cd storage
./storage.install.sh
cd ..
```

---
### install argocd
```
cd argo
./argo.install.sh
./argo.service.sh
```

### install argocd cli
```
./argo.cli.install.sh
```

### update argocd admin password
```
./argo.password.sh 'VMware1!SDDC'
```
