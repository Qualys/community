# notScannedSince.pl

This script (notScannedSince.pl) will find all assets not scanned within a number of days specified and add them to a group. We created this to work around a current limitation in asset tagging that prevents tags from being updated if a host is not scanned. Groups created with this script could be excluded from a tag in order to avoid reporting on hosts that have not been scanned recently without purging their data.

It includes usage information, but in general the syntax is like this:

	./notScannedSince.pl --username= \--password= \--serverurl= \--interval= \--groupName= [--replace]

* _serverurl_ can be either as above for the shared platform or specific to an @Customer
* _interval_ is the number of day since the current date before which you would like to add hosts to the group
* _groupname_ is the asset group you which to use for the hosts not scanned
* if you set `--replace`, the script will replace the contents of groupname with the IPs it finds, otherwise it *will* create a new group. If you omit `--replace` but use an existing name, the script will fail.

The script will create a temporary xml file that will be overwritten whenever it is run, and is currently limited to 1000 hosts.