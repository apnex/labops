---
### base OS prep
```
hostnamectl set-hostname web01
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
exec bash
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

---
### install kubectl
```
KUBERELEASE=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
curl -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBERELEASE}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client
```

### install kind
```
curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.8.1/kind-linux-amd64
chmod +x /usr/local/bin/kind
kind version
```

### clone labops
```
yum -y install git
git clone https://github.com/apnex/labops
```

### start kind
```
cd kind
./kind.start.sh
cd ..
```

### install metallb
```
cd metallb
./metallb-install.sh
cd ..
```

---
### install argocd
```
export ARGOCD_SERVER=172.19.255.1
curl -sSL -o /usr/local/bin/argocd https://${ARGOCD_SERVER}/download/argocd-linux-amd64
argocd app sync guestbook
argocd app wait guestbook
```
---
