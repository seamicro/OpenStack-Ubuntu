#!/bin/bash
#
#    orange-box-configure-openstack
#    Copyright (C) 2014 Canonical Ltd.
#
#    Authors: Darryl Weaver <darryl.weaver@canonical.com>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, version 3 of the License.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -ex

echo "This command is run to configure an Seamicro-Canonical Openstack Deployment"

PKGS=" python-keystone python-neutronclient python-novaclient python-glanceclient"
dpkg -l $PKGS > /dev/null || sudo apt-get install -y $PKGS

NEUTRON_EXT_NET_GW="192.168.140.1"
NEUTRON_EXT_NET_CIDR="192.168.140.0/22"
NEUTRON_EXT_NET_NAME="ext_net"
NEUTRON_DNS="192.168.140.25"
NEUTRON_FLOAT_RANGE_START="192.168.143.1"
NEUTRON_FLOAT_RANGE_END="192.168.143.254"

NEUTRON_FIXED_NET_CIDR="10.1.0.0/24"
NEUTRON_FIXED_NET_NAME="admin_net"

keystone=$(juju status keystone | grep public-address | head -1 | awk '{print $2}')

echo "export SERVICE_ENDPOINT=http://$keystone:35357/v2.0/
export SERVICE_TOKEN=admin
export OS_AUTH_URL=http://$keystone:35357/v2.0/
export OS_USERNAME=admin
export OS_PASSWORD=seamicro
export OS_TENANT_NAME=admin
export OS_REGION_NAME=RegionOne
" > ~/os_admin.rc

. ~/os_admin.rc

# Determine the tenant id for the configured tenant name.
export TENANT_ID="$(keystone tenant-list | grep $OS_TENANT_NAME | awk '{ print $2 }')"

#create ext network with neutron for floating IPs
EXTERNAL_NETWORK_ID=$(neutron net-create ext_net --tenant-id $TENANT_ID -- --router:external=True | grep " id" | awk '{print $4}')
neutron subnet-create ext_net $NEUTRON_EXT_NET_CIDR --name ext_net_subnet --tenant-id $TENANT_ID \
--allocation-pool start=$NEUTRON_FLOAT_RANGE_START,end=$NEUTRON_FLOAT_RANGE_END \
--gateway $NEUTRON_EXT_NET_GW --disable-dhcp --dns_nameservers $NEUTRON_DNS list=true

#Create private network for neutron for tenant VMs
neutron net-create private
SUBNET_ID=$(neutron subnet-create private $NEUTRON_FIXED_NET_CIDR -- --name private_subnet --dns_nameservers list=true $NEUTRON_DNS | grep " id" | awk '{print $4}')

#Create router for external network and private network
ROUTER_ID=$(neutron router-create --tenant-id $TENANT_ID provider-router | grep " id" | awk '{print $4}')
neutron router-interface-add $ROUTER_ID $SUBNET_ID
neutron router-gateway-set $ROUTER_ID $EXTERNAL_NETWORK_ID

#Configure the default security group to allow ICMP and SSH
nova  secgroup-add-rule default icmp -1 -1 0.0.0.0/0
nova  secgroup-add-rule default tcp 22 22 0.0.0.0/0
#for rdp
nova secgroup-add-rule default tcp 3389 3389 0.0.0.0/0

#Upload a default SSH key
nova  keypair-add --pub-key ~/.ssh/id_rsa.pub default

#Remove the m1.tiny as it is too small for Ubuntu.
nova flavor-delete m1.tiny
nova flavor-delete m1.xlarge

#Modify quotas for the tenant to allow large deployments
nova quota-update --instances 100 $TENANT_ID
nova quota-update --cores 200 $TENANT_ID
nova quota-update --ram 204800 $TENANT_ID
nova quota-update --security-groups 200 $TENANT_ID

glance image-create --name="cirros-0.3.3-x86_64a" --disk-format=qcow2 \
  --container-format=bare --is-public=true \
  --copy-from http://cdn.download.cirros-cloud.net/0.3.3/cirros-0.3.3-x86_64-disk.img

glance image-create --name="Trust x86_64a" --disk-format=qcow2 \
  --container-format=ovf --is-public=true \
  --copy-from http://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img 

glance image-create --name="Centos 64a" --disk-format=qcow2 \
  --container-format=bare --is-public=true \
  --copy-from http://mirror.catn.com/pub/catn/images/qcow2/centos6.4-x86_64-gold-master.img

exit
