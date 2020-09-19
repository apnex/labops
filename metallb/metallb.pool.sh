#!/bin/bash

ETH=$(route | grep ^default | sed "s/.* //")
IPADDRESS=$(ip addr show "${ETH}" | grep inet | awk '{print $2}' | cut -d/ -f1)

read -r -d '' METALPOOL <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${IPADDRESS}/32
EOF

echo "${METALPOOL}"
printf "${METALPOOL}" | kubectl apply -f -
