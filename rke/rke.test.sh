#!/bin/bash

echo "### create and copy ssh keys for rke user ###"
sleep 1
cat /dev/zero | ssh-keygen -q -N "" >/dev/null
yes | \cp ~/.ssh/id_rsa.pub /home/rke/.ssh/authorized_keys
chown -R rke:docker /home/rke
ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" rke@localhost << EOT
	docker version
EOT
echo "FINISHED TEST"
