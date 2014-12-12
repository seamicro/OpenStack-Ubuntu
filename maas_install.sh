# Simple Script to install MAAS on a fresh Ubuntu 14.04 Server Install

apt-get update -y
apt-get upgrade -y
apt-get dist-upgrade -y
apt-get install software-properties-common
#add-apt-repository ppa:maas-maintainers/testing (to get latest fixes we have submitted)
apt install maas
apt install juju
apt install juju-deployer
maas-region-admin createadmin --username=admin --password=seamicro --email=user@local.taz
export key=`maas-region-admin apikey --username admin`
maas login maas http://localhost/MAAS/api/1.0 $key
