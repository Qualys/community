# getscan

This script demonstrates how to interact with the QualysGuard scan functions including: Launch a scan, launch a scan and save the report on the QualysGuard server, list saved scan reports, retrieve a saved scan report, list scans in progress, and cancel a running scan.

It also demonstrates how to connect to the QualysGuard API (using basic authentication over SSL), how to provide arguments, and how to display the results of interacting with it.

Note: This script takes a username and password as the first two command line arguments.

# Dependencies For Perl

Perl versions 5.6.0 and greater are supported. 

This script relies on several freely available modules from CPAN. You will need to have the following installed:

  * Bundle::LWP — Basic WWW library
  * Net::SSL — SSL support
      * Requires OpenSSL
  * XML::Twig — Handy XML manipulation
      * Requires James Clark's expat and XML::Expat

# Legal

QualysGuard(R) MSP API Sample Code README

@(#)$Revision: 1.13 $

Copyright 2007 by Qualys, Inc. All Rights Reserved.

http://www.qualys.com