#!/bin/bash

# Working recipe of remote automated deployment of QualysGuard VirtualApplince
# to VMware vCenter/ESXi using locally stored .vmdk disk images

# Prerequisuite: VMware vSphere CLI aka Perl Toolkit, VMware OVF Tool
# Both free from VMware and available for Windows and Linux 32/64 bits.
# Version used:
# VMware ovftool 3.0.1 (build-801290)
# vSphere SDK for Perl version: 5.5.0

# Developed and tested on CentOS 5.10 x86_64

VCLI_PATH=/root/vmware-vsphere-cli-distrib/bin
OVFT_PATH=/usr/bin

VI_SERVER=iscanlab.dev.qualys.com
VI_USERNAME=root
VI_PASSWORD='*'
VI_LOCATOR="--server $VI_SERVER --username $VI_USERNAME --password $VI_PASSWORD"
DS="iscanlab:datastore2"
VC_SERVER=vcenter.vuln.qa.qualys.com
VC_USERNAME=gakimov
VC_PASSWORD='*'

VC_LOCATOR="vi://$VC_USERNAME:$VC_PASSWORD@$VC_SERVER/DEV/ML_DEV/host/$VI_SERVER"
# run ovftool "$VC_LOCATOR" once in manual mode to store SSL fingerprint or use
# --noSSLVerify with ovftool
QVMDK_PATH='[iscanlab:datastore2]/ISO Images'

PERSCODE=20100000000007
qVSA_OVA=/root/qVSA-2.0.16-2-vApp.ova
qVSA_NAME=${qVSA_OVA%.ova}; qVSA_NAME=${qVSA_NAME##*/}
QVM_NAME=qVSA-HD-Redwood-Shores-1

#.vmkd master copy should already be uploaded to datastore, but ovftool needs
# both .ovf and .vmdk locally even with --noDisks
#tar -C /tmp -xf "$qVSA_OVA"

# make sure ovf validates
$OVFT_PATH/ovftool /tmp/${qVSA_NAME}.ovf || exit $?

# make sure we can talk to ESXi directly and list datastores
$VCLI_PATH/vifs $VI_LOCATOR -S || exit $?

# manifest file breaks ovftool --noDisks method (bug in ovftool)
# this command runs on vCenter
#$OVFT_PATH/ovftool --noDisks --skipManifestCheck -dm=thin -n="$QVM_NAME" --prop:Personalization_Code=$PERSCODE --ipAllocationPolicy=dhcpPolicy --net:LAN='VM VLAN3' --net:WAN='VM VLAN3' --prop:LAN_Default_VLAN=103 -ds="$DS" /tmp/${qVSA_NAME}.ovf "$VC_LOCATOR" || exit $?

# both --net:LAN and --net:WAN= must always be provided
# --prop:LAN_Default_VLAN is optional
# --ipAllocationPolicy=fixedPolicy is only advisory
# if --prop:LAN_IP= is not set, appliance defaults to DHCP
$OVFT_PATH/ovftool --noDisks --skipManifestCheck -dm=thin -n="$QVM_NAME" --prop:Personalization_Code=$PERSCODE \
--net:LAN='VM VLAN3' --net:WAN='VM VLAN3' \
--ipAllocationPolicy=fixedPolicy \
--prop:LAN_Default_VLAN=103 \
--prop:LAN_IP=10.40.9.10 --prop:LAN_Netmask=255.255.255.0 \
--prop:LAN_Gateway=10.40.9.1 --prop:LAN_DNS_Servers=10.0.100.10,10.0.100.11 \
-ds="$DS" /tmp/${qVSA_NAME}.ovf "$VC_LOCATOR" || exit $?

$VCLI_PATH/vifs $VI_LOCATOR -D "[$DS]$QVM_NAME/" || exit $?

# remove empty .vmkd disk created by ovftool
$VCLI_PATH/vmkfstools $VI_LOCATOR -U "[$DS]$QVM_NAME/$QVM_NAME.vmdk" || exit $?

# clone master .vmdk - runs locally on ESXi server
$VCLI_PATH/vmkfstools $VI_LOCATOR -d thin -i "$QVMDK_PATH/$qVSA_NAME-disk1.vmdk" "[$DS]$QVM_NAME/$QVM_NAME.vmdk" || exit $?

# MUST be run on vCenter to create run-time ovfEnv XML structure
$VCLI_PATH/vmware-cmd -H "$VC_SERVER" -h "$VI_SERVER" -U "$VC_USERNAME" -P "$VC_PASSWORD" "/vmfs/volumes/$DS/$QVM_NAME/$QVM_NAME.vmx" start
