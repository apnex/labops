#!/bin/bash
kubectl -n argocd delete services argocd-server
kubectl -n argocd apply -f argo.vip.yaml

#kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
#PATCH=$(jq -nc '{
#	"spec": {
#		"ports": [
#			{
#				"name": "https",
#				"port": 8472,
#				"protocol": "TCP",
#				"targetPort": 8080
#			}
#		],
#		"type": "LoadBalancer"
#	}
#}')
#printf "${PATCH}" | jq --tab .
#kubectl patch svc argocd-server -n argocd --type merge -p "${PATCH}"
