# addassetip

This script adds asset IP addresses to a QualysGuard subscription by importing the assets from a CSV file. This script may be run using an account that is defined with the Manager user role.

Using this script, you can bulk populate IP addresses and related host information in QualysGuard using asset data already available in spreadsheets or data exported from a database. The script demonstrates this capability by taking properly formatted CSV data with user-supplied asset attributes as input, and transforming this input into a URL that will populate the QualysGuard account with asset information. 

The CSV file and user-supplied attributes are provided in the addassetip.conf file, which is provided with this script. The CSV file must have a single column with each row containing a single IP address or an IP range.

Please note that the amount of asset data that can be imported into QualysGuard using this script is limited by the number of characters allowed in a single URL. For this reason it is recommended that you specify IP ranges to overcome this limitation.

Note: This script takes a username and password as the first two command line arguments.

# Dependencies For Perl

Perl versions 5.6.0 and greater are supported. 

This script relies on several freely available modules from CPAN. You will need to have the following installed:

  * Bundle::LWP — Basic WWW library
  * Net::SSL — SSL support
      * Requires OpenSSL
  * XML::Twig — Handy XML manipulation
      * Requires James Clark's expat and XML::Expat
  * Config::Simple;
  * HTTP::Request;
  * LWP::UserAgent;

# Legal

QualysGuard(R) MSP API Sample Code README

@(#)$Revision: 1.13 $

Copyright 2007 by Qualys, Inc. All Rights Reserved.

http://www.qualys.com