# labops.sh
## declarative gitops for compelling demo environments

### start with a minimal CentOS 7 VM
CPU: 4 vCPU  
MEM: 4 GB  
DISK: 32 GB  

[https://github.com/apnex/pxe](https://github.com/apnex/pxe)

---
### install docker
```
curl -fsSL http://labops.sh/docker/install | sh
```

### install rke
```
curl -fsSL http://labops.sh/rke/install | sh
```

### check cluster
```
kubectl get nodes
kubectl get pods -A
```

### clone labops
```
yum -y install git
git clone https://labops.sh
cd labops
```
