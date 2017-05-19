Ipconvert
==========
This script converts Qualys network range output to CIDR blocks. Script requires Python 3 ipaddress module.  Script can be easily modify to output network mask, host mask or prefix length (default).
 
Input 
10.127.2.1-10.127.2.2
10.127.2.4
10.127.3.0-10.127.3.7
10.127.5.0-10.127.5.31

Output
10.127.2.1/32
10.127.2.2/32
10.127.2.4/32
10.127.3.0/29
10.127.5.0/27
