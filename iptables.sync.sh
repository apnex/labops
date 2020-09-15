#!/bin/sh
# This script uses kubectl to poll the kubernetes API for Service.type = LoadBalancer entities in KIND
# These are converted into local iptables DNAT entries and published on the host every 10 seconds

MYIF="eth0"
MYCHAIN="KINDNAT"

#iptables -t nat -L ${MYCHAIN} &>/dev/null
#if [ "$?" -eq "0" ]; then
#	iptables -F ${MYCHAIN}
#else
#	iptables -N ${MYCHAIN}
#fi

while [ 1 ]; do
	## delete NATCHAIN
	iptables -t nat -D PREROUTING -i ${MYIF} -j ${MYCHAIN} &>/dev/null
	iptables -t nat -F ${MYCHAIN} &>/dev/null
	iptables -t nat -X ${MYCHAIN} &>/dev/null

	## create NATCHAIN
	iptables -t nat -N ${MYCHAIN}
	iptables -t nat -A PREROUTING -i ${MYIF} -j ${MYCHAIN}

	## fill NATCHAIN
	IFS=$'\n'
	COUNTER=0
	for ITEM in $(kubectl get svc -A -o json | jq -f loadBalancer.jq | jq -r '.[]'); do
		RULE="iptables -t nat -A ${MYCHAIN} -i ${MYIF} ${ITEM}"
		#echo "|| ${RULE} ||"
		COUNTER=$(( $COUNTER + 1 ))
		$(eval "${RULE}")
	done

	## sleep
	echo "Rules synchronised to host - num [ ${COUNTER} ]"
	sleep 10
done

## Update to use this to check for, and delete rules
## match and convert to JSON, then use loadBalancer.jq to rebuild rule
## iptables -t nat -S KINDNAT
