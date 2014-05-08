# getmap

This script demonstrates how to interact with the QualysGuard network map functions including: Launch a map, launch a map and save the report on the QualysGuard server, list saved map reports, retrieve a saved map report, list maps in progress, and cancel a running map.

It also demonstrates how to connect to the QualysGuard API (using basic authentication over SSL), how to pass arguments, and how to display the results of interacting with it.

If called with a netblock-delimited domain, or a list of domains, then the map-2.php API call is used (otherwise the map.php call will be used by default).

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