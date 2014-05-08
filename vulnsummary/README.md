# vulnsummary

This script demonstrates how to connect to the QualysGuard API and how to extract vulnerability data from the scan report XML document.

It returns a list of vulnerabilities, the IP address(es) affected, their severity, and a short description of each.

The scan report XML document, which contains the vulnerability data for a particular scan, is obtained by executing a scan when the script runs or by retrieving a previously saved scan report.

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