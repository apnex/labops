# labops.sh
**declarative gitops for compelling lab and demo environments**  

## What is it
labops.sh is a collection of bootstrap scripts organised to provide simple automation of multi-tier microservices applications for demo purposes.  


Simple
- Clear and minimal entrypoints to start, fewest steps to known good

Modular
- Multiple components with clear and simple functions that built upon each other

Serviceable  
- Can easily be modified or extended, no logic hidden or embedded in hard to find places

Portable  
- Designed with minimal or no external dependencies so it can be run on on virtualised public or private cloud environment  

It leverages Kubernetes and GitOps to declaratively publish

## TLDR;

### start with a minimal CentOS 7 VM
CPU: 4 vCPU  
MEM: 4 GB  
DISK: 32 GB  

[https://github.com/apnex/pxe](https://github.com/apnex/pxe)

### 
It is built to be highly modular, with 

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
