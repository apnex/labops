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

### enable ip-forwarding
```
cat <<-EOF > /etc/sysctl.d/k8s.conf
	net.bridge.bridge-nf-call-ip6tables = 1
	net.bridge.bridge-nf-call-iptables = 1
	net.ipv4.ip_forward = 1
EOF
sysctl --system
```

### check.modules
```
for module in br_netfilter ip6_udp_tunnel ip_set ip_set_hash_ip ip_set_hash_net iptable_filter iptable_nat iptable_mangle iptable_raw nf_conntrack_netlink nf_conntrack nf_conntrack_ipv4   nf_defrag_ipv4 nf_nat nf_nat_ipv4 nf_nat_masquerade_ipv4 nfnetlink udp_tunnel veth vxlan x_tables xt_addrtype xt_conntrack xt_comment xt_mark xt_multiport xt_nat xt_recent xt_set xt_statistic xt_tcpudp;
do
	if [[ ! lsmod | grep -q $MODULE ]]; then
		echo "module $MODULE is not present";
	fi;
done
```
### reload br_filter
```
echo br_netfilter > /etc/modules-load.d/br_netfilter.conf
modprobe br_netfilter
lsmod | grep br_netfilter
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
usermod -aG docker <user_name>
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

#### v1.18.8-rancher1-1
### install rke
---
curl -Lo /usr/local/bin/rke https://github.com/rancher/rke/releases/download/v1.1.7/rke_linux-amd64
chmod +x /usr/local/bin/rke
rke --version
---

### clone labops
```
yum -y install git
git clone https://github.com/apnex/labops
cd labops
```

---
### install argocd
```
cd argo
./argo.install.sh
./argo.patch.sh
```

### install argocd cli
```
read -r -d '' FILTER <<-'EOF'
	.status.loadBalancer.ingress[0].ip as $IP
	| $IP + ":" + (.spec.ports[0].port|tostring)
EOF
export ARGOCD_SERVER=$(kubectl -n argocd get services vip-argocd-server -o json | jq -r "${FILTER}")
curl -kLo /usr/local/bin/argocd https://${ARGOCD_SERVER}/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
argocd version --insecure
```

### update argocd admin password
```
./argo.password.sh 'VMware1!SDDC'
```
