#!/bin/bash
read -r -d '' MODULELIST <<'EOF'
[
	"br_netfilter",
	"ip6_udp_tunnel",
	"ip_set",
	"ip_set_hash_ip",
	"ip_set_hash_net",
	"iptable_filter",
	"iptable_nat",
	"iptable_mangle",
	"iptable_raw",
	"nf_conntrack_netlink",
	"nf_conntrack",
	"nf_conntrack_ipv4",
	"nf_defrag_ipv4",
	"nf_nat",
	"nf_nat_ipv4",
	"nf_nat_masquerade_ipv4",
	"nfnetlink",
	"udp_tunnel",
	"veth",
	"vxlan",
	"x_tables",
	"xt_addrtype",
	"xt_conntrack",
	"xt_comment",
	"xt_mark",
	"xt_multiport",
	"xt_nat",
	"xt_recent",
	"xt_set",
	"xt_statistic",
	"xt_tcpudp"
]
EOF
for MODULE in $(printf "${MODULELIST}" | jq -r '.[]'); do
	if [[ $(lsmod | grep ${MODULE}) ]]; then
		echo "module ${MODULE} is LOADED";
	elif [[ $(cat /lib/modules/$(uname -r)/modules.builtin | grep ${MODULE}) ]]; then
		echo "module ${MODULE} is BUILTIN";
	else
		echo "module ${MODULE} is MISSING";
		modprobe ${MODULE}
	fi;
done
