### start with a minimal CentOS 7 VM
CPU: 4 vCPU  
MEM: 4 GB  
DISK: 32 GB  

[https://github.com/apnex/pxe](https://github.com/apnex/pxe)

---
### install docker
```
curl -fsSL https://docker.labops.sh/install | sh
```

### install rke
```
curl -fsSL https://rke.labops.sh/install | sh
```

### check cluster
```
kubectl get nodes
kubectl get pods -A
```

### clone labops
```
yum -y install git
git clone https://github.com/apnex/labops
cd labops
```
