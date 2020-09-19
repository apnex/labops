### clone labops
```
yum -y install git
git clone https://github.com/apnex/labops
cd labops
```

### docker user
```
useradd -m -g docker rke
mkdir -p /home/rke/.ssh
chmod 700 /home/rke/.ssh
chmod -R go= /home/rke/.ssh
```

### create and copy ssh keys to rke user
```
cat /dev/zero | ssh-keygen -q -N "" >/dev/null
cp ~/.ssh/id_rsa.pub /home/rke/.ssh/authorized_keys
chown -R rke:docker /home/rke
ssh rke@localhost docker version
```

### install rke
```
curl -Lo /usr/local/bin/rke https://github.com/rancher/rke/releases/download/v1.2.0-rc10/rke_linux-amd64
chmod +x /usr/local/bin/rke
rke --version
```

### install kubectl
```
KUBERELEASE=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
curl -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBERELEASE}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client
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

### check cluster
```
kubectl get nodes
kubectl get pods -A
```
