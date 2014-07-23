
#Set static variables
$OVFTool = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
$Vappliance_ovffile = "h:\qualys\qVSA-2.0.16-2.ovf"
$Vappliance_portgroup = "QualysVPort"
#$Vappliance_portgroup = "stqualysVPort"

#Get credentials to authenticate against VCenter
$creds = Get-Credential "Enter credentials"
$cred_name = $($creds.username)
$cred_pass = $($creds.getnetworkcredential().password)

#Read list of stores to be deployed.
$deploylist = Import-Csv h:\qualys\storeconfig.csv 

foreach ($targetstore in $deploylist)
{
#$targetstore | Format-List
$VCName = "XXXXXX"

$storenumber = $targetstore.STORE
$VHost = "stvt04."+$storenumber+".homedepot.com"
$Vdatacenter = $targetstore.STORE.ToUpper()
$Vappliance_datastore = $storenumber+"smvsa02"
$Vappliance_name = "stqualys."+$storenumber+".homedepot.com"
$Vappliance_path = "["+$Vappliance_datastore+"] "+$Vappliance_name
$Vappliance_IP = $targetstore.IP_ADDRESS
$Vappliance_Subnet = $targetstore.SUBNET
$Vappliance_gateway = $targetstore.GATEWAY
$Vappliance_DNS = $targetstore.DNS1+","+$targetstore.DNS2
$Vappliance_pcode = $targetstore.ACTIVATION_CODE
$VMDK_datastore = "stvt04_"+$storenumber+"_vmfs01"
$VMDK_target = "["+$VMDK_datastore+"] "+ "/qVSA-2.0.16-2-vApp-disk1.vmdk"
$VMDK_newdisk = $Vappliance_path +"/qVSA-2.0.16-2-vApp-disk1.vmdk"


#Connect and authenticate to VCenter
#Connect-VIServer $VCName -Credential $creds
#Connect-VIServer XXXXXXX
# Get session and ticket
#$VSession = Get-View -server $VCName -Id Sessionmanager
#$VTicket = $Session.AcquireCloneTicket()

Write-Host "--noDisks"  "--name=$($Vappliance_name)" "--noSSLVerify" "--skipManifestCheck" "--prop:Personalization_Code=$($Vappliance_pcode)" "--prop:LAN_IP=$($Vappliance_IP)" "--prop:LAN_Netmask=$($Vappliance_subnet)" "--prop:LAN_Gateway=$($Vappliance_gateway)" "--prop:LAN_DNS_Servers=$($Vappliance_DNS)" "--datastore=$($Vappliance_datastore)" "--ipAllocationPolicy=fixedPolicy" "--net:LAN=$($Vappliance_portgroup)" "--net:WAN=$($Vappliance_portgroup)" "$($Vappliance_ovffile)" "vi://$($cred_name):$($cred_pass)@$($VCName)/LAB/$($Vdatacenter)/host/$($Vdatacenter)/$($VHost)"
& $OVFTool "--noDisks"  "--name=$($Vappliance_name)" "--noSSLVerify" "--skipManifestCheck" "--prop:Personalization_Code=$($Vappliance_pcode)" "--prop:LAN_IP=$($Vappliance_IP)" "--prop:LAN_Netmask=$($Vappliance_subnet)" "--prop:LAN_Gateway=$($Vappliance_gateway)" "--prop:LAN_DNS_Servers=$($Vappliance_DNS)" "--datastore=$($Vappliance_datastore)" "--ipAllocationPolicy=fixedPolicy" "--net:LAN=$($Vappliance_portgroup)" "--net:WAN=$($Vappliance_portgroup)" "$($Vappliance_ovffile)" "vi://$($cred_name):$($cred_pass)@$($VCName)/LAB/$($Vdatacenter)/host/$($Vdatacenter)/$($VHost)"
#Write-Host "--noDisks" "--name=$($Vappliance_name)" "--skipManifestCheck" "--prop:Personalization_Code=$($Vappliance_pcode)" "--prop:LAN_IP=$($Vappliance_IP)" "--prop:LAN_Netmask=$($Vappliance_subnet)" "--prop:LAN_Gateway=$($Vappliance_gateway)" "--prop:LAN_DNS_Servers=$($Vappliance_DNS)" "--datastore=$($Vappliance_datastore)" "--ipAllocationPolicy=fixedPolicy" "--net:LAN=$($Vappliance_portgroup)" "--net:WAN=$($Vappliance_portgroup)" "$($Vappliance_ovffile)" "vi://$($cred_name):$($cred_pass)@$($VCName)/$($Vdatacenter)/host/$($Vdatacenter)/$($VHost)"

Get-VM $Vappliance_name | Get-HardDisk | Remove-HardDisk -DeletePermanently -Confirm:$false
$qualys_vmdk = Get-HardDisk -Datastore $VMDK_datastore -DatastorePath $VMDK_target
Copy-HardDisk -HardDisk $qualys_vmdk -DestinationPath $Vappliance_path -Confirm:$false
Get-VM $Vappliance_name | New-HardDisk -DiskPath $VMDK_newdisk
Start-VM -VM $Vappliance_name -Confirm:$false 
#Remove-HardDisk -HardDisk $qualys_vmdk -Confirm:$false 
Disconnect-VIServer $VCName -Confirm:$false 
}
