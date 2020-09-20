#!/bin/bash

curl -Lo ./jid_linux_amd64.zip https://github.com/simeji/jid/releases/latest/download/jid_linux_amd64.zip
yum install -y unzip
unzip jid_linux_amd64.zip -d /usr/local/bin/
chmod +x /usr/local/bin/jid

