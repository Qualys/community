# usercreate

This script adds user accounts to an existing subscription by importing user account information from a user-defined CSV file. This script may be run using an account that is defined for a Manager or Unit Manager.

When the script is run, new users are added based on user-defined parameters provided in the usercreate.conf file and a CSV file. The script parses every row of the given comma separated file , which defines account parameters for users to be added. The columns correspond to input parameters for the user.php API function, 
which is documented in the QualysGuard API User Guide. Rows for required user.php API parameters must be specified. A sample CSV file is provided, with columns for the various parameters required to invoke the user.php API call.

Note: This script takes a username and password as the first two command line arguments.

# Dependencies For Perl

Perl versions 5.6.0 and greater are supported. 

This script relies on several freely available modules from CPAN. You will need to have the following installed:

  * Bundle::LWP — Basic WWW library
  * Net::SSL — SSL support
      * Requires OpenSSL
  * XML::Twig — Handy XML manipulation
      * Requires James Clark's expat and XML::Expat
  * URI::Escape;

# Legal

QualysGuard(R) MSP API Sample Code README

@(#)$Revision: 1.13 $

Copyright 2007 by Qualys, Inc. All Rights Reserved.

http://www.qualys.com