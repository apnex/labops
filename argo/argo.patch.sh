#!/bin/bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

## below doesnt yet work - need to fix
#cat <<'EOF' | kubectl -n argocd patch svc argocd-server --type=json -p -
#{
#	"spec": {
#		"type": "LoadBalancer"
#	}
#}
#EOF
