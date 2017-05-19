#!/usr/bin/python3

# Script requires Python 3 ipaddress module
# This script converts Qualys network range output to CIDR blocks

# Input file example: 
# 10.127.2.1-10.127.2.2
# 10.127.2.4
# 10.127.3.0-10.127.3.7
# 10.127.5.0-10.127.5.31
# Output:
# 10.127.2.1/32
# 10.127.2.2/32
# 10.127.2.4/32
# 10.127.3.0/29
# 10.127.5.0/27

import ipaddress
from sys import argv

def getCIDR(sip,eip):
    ''' returns one or more CIDR ranges for start and end IP range '''
    # is it a qualys range?
    startip = ipaddress.IPv4Address(sip)
    endip = ipaddress.IPv4Address(eip)
    # summarized cidr ranges
    yield ([ipaddr for ipaddr in ipaddress.summarize_address_range(startip, endip)])

def qualys2cidr(infile):
    with open(infile,'r') as input:
        blacklist = [line.split('-') for line in input.read().splitlines()]
        for ipblock in blacklist:
            try:
                if len(ipblock) == 2:
                    ranges = getCIDR(ipblock[0].strip(),ipblock[1].strip())
                else:
                    ranges = getCIDR(ipblock[0].strip(),ipblock[0].strip())
                    
                # Iterate over summarized CIDR ranges and output
                for cidrs in ranges:
                    if type(cidrs) == list:
                        for cidr in cidrs:
                            # with_prefixlen = /32
                            # with_netmask = /255.255.255.255
                            # with_hostmask = /0.0.0.0
                            print(cidr.with_prefixlen)
            except:
                print("Failed to process: %s. SKIPPED." % ipblock)


if __name__ == "__main__":
    if len(argv) < 2:
        print("%s <qualys network ranges>" % argv[0])
    else:
        qualys2cidr(argv[1])
