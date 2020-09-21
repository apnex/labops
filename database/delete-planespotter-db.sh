#!/bin/bash

cd ~/planespotter/db-install/
mysql --local_infile=1 --user=root --password=$MYSQL_ROOT_PASSWORD < delete-planespotter-db.sql
