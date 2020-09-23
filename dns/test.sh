#!/bin/bash

#dig @172.20.48.52 test.lab.svc.cluster.local

ARECORD=$(dig @172.20.48.52 test.lab04)

echo ${ARECORD}
echo

dig @172.20.48.52 -x 8.8.8.8
