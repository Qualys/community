hostdetection.pl
----------------
Very high level example of how to pull the hostdetection data with the API

-f does a full pull to date, alternatively use -d YYYY-MM-DD to get a delta pull from given date


# Dependencies For Perl

Perl versions 5.14.0 and greater are supported. 

This script relies on several freely available modules from CPAN. You will need to have the following installed:

  * Data::Dumper — basic Datadump module
  
multi_thread_hd.py
------------------
Example code for pulling the host detection data in multi thhreads using a simple queing system in python
