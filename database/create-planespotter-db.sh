#!/bin/bash

cd ~/planespotter/db-install/
curl -Lo ReleasableAircraft.zip http://registry.faa.gov/database/ReleasableAircraft.zip
unzip ReleasableAircraft.zip
rm ReleasableAircraft.zip DEALER.txt DEREG.txt DOCINDEX.txt ENGINE.txt RESERVED.txt
mysql --local_infile=1 --user=root --password=${MYSQL_ROOT_PASSWORD} < create-planespotter-db.sql
rm MASTER.txt ACFTREF.txt
