# `labops.sh`
**declarative gitops for compelling lab and demo environments**  

![labops-app](argo-network.gif)

## What is it
`labops.sh` is a collection of bootstrap scripts organised to provide simple automation of multi-tier microservices applications for demo purposes.  

It creates VMs that are designed to be fully self-assembling, building upon each layer to the next, resulting in a fully functioning single-node Kubernetes cluster.  

It is engineered to be:  

**Simple**
- Clear and minimal entrypoints to start, fewest steps to known good

**Modular**
- Multiple components with clear and simple functions that build upon each other

**Serviceable**  
- Can easily be modified or extended, no logic hidden or embedded in hard to find places

**Portable**
- Designed with minimal or no external dependencies so it can be run on any public or private cloud environment  

After provisioning a VM, a fully working web application can then be deployed via the in-built catalogue.
This reachable via:
- https://X.X.X.X:8472
- `admin` / `VMware1!`

By being modular and declarative, a `labops.sh` node can quickly be repurposed or have its microservices application changed.  

---
## TLDR; Quick Start
The base VM image is currently built on Centos 7.  
It is deployed through an unattended network installation over the Internet.  
Once booted, multiple packages are then bootstrapped to finalise the node.  

To use a completed node, simply download the pre-made ISO from here:  
https://labops.sh/boot.iso

This is a tiny 1MB ISO - as it contains only iPXE code.  
All remaining OS files will be bootstrapped over the Internet via HTTP.  
Just mount this ISO to a CDROM of a VM and power on.  

**Warning**: Ensure you have created your VM with the following settings:  

Minimum VM Specifications:  
- CPU: 4  
- MEM: 4 GB  
- DSK: 32 GB  

Boot Order (must be **BIOS**):  
- 1: HDD  
- 2: CDROM

This is to ensure that after installation, the VM will boot normally.  
If CDROM is before HDD, the VM will be in an infinite loop restarting and rebuilding itself!  

Once powered on, the `labops.sh` VM automatically evolves through 4 distinct, yet decoupled stages.  
This could take up to 10 minutes, depending on Internet speeds - be patient and grab a coffee!  

Optionally, you can elect to download the ISO directly for that particular stage.  
This will allow you to stop there and customise your configuration.  

Default root ssh/console credentials:  `root` / `VMware1!`  

---
### 1. `base` node
- Minimal unattended network installation of Centos 7 OS streamed over the Internet.
- No extraneous packages outside minimal core  
- Suitable for a wide variety of lab and demo tasks  

Get the iso here:  
https://labops.sh/base/boot.iso  

More information on `base` node:  
https://github.com/apnex/pxe  

### 2. `docker` node
- Builds upon **1**, and prepares the node for Docker suitable for container use
- Useful for labs requiring a docker VM  

Get the iso here:  
https://labops.sh/docker/boot.iso  

### 3. `rke` node
- Builds upon **2**, and provisions Kubernetes suitable for single-appliance use
- All-in-one k8s node suitable for local microservices deployment
- Batteries included - support for Service Type=LoadBalancer and Dynamic PVCs

Get the iso here:  
https://labops.sh/rke/boot.iso  

### 4. `labops` node
- Builds upon **3**, and deploys the Argo CD platform for an automated microservices control-plane on the node
- Automatically evolves through all 4 stages ready for microservices application deployment

Get the iso here:  
https://labops.sh/boot.iso

---
## Verification
Once you have deployed a VM to stage 3 or 4, you can login with the default SSH credentials and verify status.  

### check local cluster
```
kubectl get nodes
kubectl get pods -A
```

The node will be pulling images from DockerHub, this could take a few minutes to start.  

### clone labops
Optionally, for access to all `labops.sh` scripts, you can clone this repository.  
```
yum -y install git
git clone https://labops.sh
cd labops.sh
```
