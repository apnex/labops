#!/bin/bash

cd ~/planespotter/db-install/
curl -Lo MASTER.txt https://raw.githubusercontent.com/apnex/labops/master/database/FAKE-MASTER.txt
curl -Lo ACFTREF.txt https://raw.githubusercontent.com/apnex/labops/master/database/FAKE-ACFTREF.txt
mysql --local_infile=1 --user=root --password=${MYSQL_ROOT_PASSWORD} < create-planespotter-db.sql
rm MASTER.txt ACFTREF.txt
