#!/usr/bin/perl

###############################################
###                                         ###
### install modules required by TNE         ###
###                                         ###
###                                         ###
###                                         ###
###                                         ###
###############################################


use CPAN;
use strict;
use warnings;

my @module_list = qw(
		   Date::Parse
		   URI::Escape
		   LWP::UserAgent
		   Net::SMTP
		   Text::Template
		   Config::Simple
		   LockFile::Simple
		   XML::Twig
		   XML::XPath
		   XML::Simple
		   Data::Dumper
		   Storable
		   Getopt::Long
		   Crypt::SSLeay
		   );




for my $module ( @module_list ){
  CPAN::Shell->install($module);
}
