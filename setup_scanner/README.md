setupscanner.pl
=============
For setting up the scanners before deployment to your virtualization infrastructure.  You need the activation codes output from this script to do that.  

Written to help a customer who wanted to deploy thousands of virtual scanners to their retail store environment (a scnner per store).  YOu must create the stores.csv list initially and place in running directory.

Output is storesconfig.csv

deployQVappliance.ps1
==============
Example Powershell code utilizing VMWARE PowerCLI extensions to deploy the scanners into remote locations ESXi servers and spin up the VM's.  Probably need customization for your environment
