All of the files in the subdirectoy are for deploying scanners automatically in very large environments.  Any questions please contact Jeff leggett at jleggett@qualys.com


setupscanner.pl
=============
For setting up the scanners before deployment to your virtualization infrastructure.  You need the activation codes output from this script to do that.  

Written to help a customer who wanted to deploy thousands of virtual scanners to their retail store environment (a scnner per store).  YOu must create the stores.csv list initially and place in running directory.

Output is storesconfig.csv

QAPIsetupscanner.go
===================
Similar but more generic functionality to the Perl script above, re-written in GO language

configscanner.pl
==============
For configuring the scanners defined with the setupscanner.pl script, this will create the asset groups, assign the scanner to that AG, setup VLAN's appropriately, and get it ready to scan.  Provided as example only, will need customization for YOUR environment.

ovf_brew-distrib.sh
==============
Example shell code utilizing VMWARE PowerCLI extensions to deploy the scanners into remote locations ESXi servers and spin up the VM's.  Probably need customization for your environment

deployQVappliance.ps1
==============
Example Powershell code utilizing VMWARE PowerCLI extensions to deploy the scanners into remote locations ESXi servers and spin up the VM's.  Probably need customization for your environment
