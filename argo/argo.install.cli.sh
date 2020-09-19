#!/bin/bash
read -r -d '' FILTER <<-'EOF'
	def extIP:
		if (.spec.externalIPs[0]?) != 0 then
			.spec.externalIPs[0]
		else
			.status.loadBalancer.ingress[0].ip
		end
	;
	extIP as $IP
	| $IP + ":" + (.spec.ports[0].port | tostring)
EOF
export ARGOCD_SERVER=$(kubectl -n argocd get services vip-argocd-server -o json | jq -r "${FILTER}")
curl -kLo /usr/local/bin/argocd https://${ARGOCD_SERVER}/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
argocd version --insecure
